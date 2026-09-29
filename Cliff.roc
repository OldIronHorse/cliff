Cliff := {}.{
    Raw : { opts: Dict(Str, List(Str)), params: List(Str) }

    TokenError : [
        UnknownOption(Str),
        MissingValue(Str),
        UnexpectedValue(Str),
        RepeatedOption(Str),
    ]

    tokenise : List(Str), List(Cliff.Opt.Info) -> Try(Raw, TokenError)
    tokenise = |argv, infos| {
        infos_by_name = infos.map(|i| (i.long, i))
            .concat(infos.drop_if(|i| i.short.is_empty()).map(|i| (i.short, i)))
            .fold_try(Dict.empty(), |d, (k, v)|
                if d.contains(k)
                    Err(RepeatedOption(k))
                else
                    Ok(d.insert(k, v)))?

        do = |args, raw|
            match args {
                [] => Ok(raw)
                [opt, .. as rest] if opt.starts_with("--") =>
                    match opt.drop_prefix("--").split_first("=") {
                        Ok({ before, after }) => {
                            match infos_by_name.get(before) {
                                Ok(i) =>
                                    match i.kind {
                                        Value =>
                                            do(rest, { ..raw, opts: raw.opts.insert(i.long, [after]) })
                                        _ =>
                                            Err(UnexpectedValue(after))
                                    }
                                _ => Err(UnknownOption(opt))
                            }
                        }
                        Err(NotFound) => {
                            match infos_by_name.get(opt.drop_prefix("--")) {
                                Ok(i) => {
                                    match i.kind {
                                        Value => Err(MissingValue(opt))
                                        _ =>
                                            do(rest, { ..raw, opts: raw.opts.update(i.long, |old_value|
                                                match old_value {
                                                    Err(Missing) => Ok([""])
                                                    Ok(vs) => Ok(vs.append(""))
                                                }) })
                                    }
                                }
                                _ => Err(UnknownOption(opt))
                            }
                        }
                    }
                [opt, .. as rest] if opt.starts_with("-") =>
                    do(rest, opt.drop_prefix("-")
                        .to_utf8()
                        .fold_try(raw, |r, c|
                            match Str.from_utf8([c]) {
                                Ok(s) =>
                                    match infos_by_name.get(s) {
                                        Err(KeyNotFound) => Err(UnknownOption("-${s}"))
                                        Ok(info) =>
                                            Ok({ ..r, opts: r.opts.update(info.long, |old_value|
                                                match old_value {
                                                    Err(Missing) => Ok([""])
                                                    Ok(vs) => Ok(vs.append(""))
                                                })
                                            })
                                    }
                                _ => Err(UnexpectedValue(opt))
                            })?)
                [opt, ..] => Err(UnknownOption(opt))
            }

        do(argv, { opts: Dict.empty(), params: [] })
    }

    Opt := {}.{
        Kind : [Flag, Count, Value, Values]
        Info := { kind: Kind, long: Str, short: Str ?? "", help: Str ?? "" }.{
            is_eq = |self, other|
                self.kind == other.kind
                    and self.short == other.short
                    and self.long == other.long
                    and self.help == other.help
        }
        Spec(a) := { info: Info, convert: List(Str) -> Try(a, [TypeMismatch, NotFound]) }.{
            count : Str -> Spec(I64)
            count = |long| Spec.{ info: Info.{ kind: Count, long }, convert: dummy }

            flag : Str -> Spec(Bool)
            flag = |long| Spec.{ info: Info.{ kind: Flag, long }, convert: dummy }

            value : Str -> Spec(Str)
            value = |long| Spec.{ info: Info.{ kind: Value, long }, convert: dummy }

            short : Spec(a), Str -> Spec(a)
            short = |spec, s| { ..spec, info: { ..spec.info, short: s } }

            help : Spec(a), Str -> Spec(a)
            help = |spec, s| { ..spec, info: { ..spec.info, help: s } }
        }
    }
    Param := {}.{
        Kind : [Value, Values]
        Info := { kind: Kind, name: Str, help: Str ?? "" }.{
            is_eq = |self, other|
                self.kind == other.kind
                    and self.name == other.name
                    and self.help == other.help
        }
        Spec(a) := { info: Info, convert: List(Str) -> Try(a, [TypeMismatch, NotFound])}.{
            str : Str -> Spec(Str)
            str = |name| Spec.{ info: Info.{ name, kind: Value }, convert: dummy }

            strs : Str -> Spec(List(Str))
            strs = |name| Spec.{ info: Info.{ name, kind: Values }, convert: dummy}

            help : Spec, Str -> Spec
            help = |spec, s| { ..spec, info: { ..spec.info, help: s }}
        }
    }
}

dummy : List(Str) -> Try(a, [TypeMismatch, NotFound])
dummy = |_| Err(NotFound)

expect
    Cliff.Opt.Info.{ kind: Count, short: "v", long: "verbosity", help: "verbosity level" }
        == Opt.Spec.count("verbosity").short("v").help("verbosity level").info
expect
    Cliff.Param.Info.{ kind: Value, name: "file", help: "the file to load" }
        == Param.Spec.str("file").help("the file to load").info

expect Dict.from_list([("verbosity", [""])])
    == Cliff.tokenise(["--verbosity"], [Opt.Spec.count("verbosity").short("v").info])?.opts
expect Dict.from_list([("verbosity", [""])])
    == Cliff.tokenise(["-v"], [Opt.Spec.count("verbosity").short("v").info])?.opts
expect Dict.from_list([("verbosity", ["", ""])])
    == Cliff.tokenise(["-v", "-v"], [Opt.Spec.count("verbosity").short("v").info])?.opts
expect Dict.from_list([("verbosity", ["", "", ""])])
    == Cliff.tokenise(["-vvv"], [Opt.Spec.count("verbosity").short("v").info])?.opts
expect Dict.from_list([("verbosity", [""]), ("exclusive", [""])])
    == Cliff.tokenise(
        ["-v", "-x"],
        [
            Opt.Spec.count("verbosity").short("v").info,
            Opt.Spec.count("exclusive").short("x").info,
        ])?.opts
expect Dict.from_list([("verbosity", [""]), ("exclusive", [""])])
    == Cliff.tokenise(
        ["--verbosity", "--exclusive"],
        [
            Opt.Spec.count("verbosity").short("v").info,
            Opt.Spec.count("exclusive").short("x").info,
        ])?.opts
expect Dict.from_list([("verbosity", ["", ""]), ("exclusive", [""])])
    == Cliff.tokenise(
        ["-vxv"],
        [
            Opt.Spec.count("verbosity").short("v").info,
            Opt.Spec.count("exclusive").short("x").info,
        ])?.opts
expect Dict.from_list([("verbosity", ["", ""]), ("exclusive", ["", ""])])
    == Cliff.tokenise(
        ["-vxv", "-x"],
        [
            Opt.Spec.count("verbosity").short("v").info,
            Opt.Spec.count("exclusive").short("x").info,
        ])?.opts
expect Err(UnknownOption("-x"))
    == Cliff.tokenise(["-x"], [Opt.Spec.count("verbosity").short("v").info])
expect {
    Err(UnknownOption("--excl"))
        == Cliff.tokenise(["--excl"], [Opt.Spec.count("verbosity").short("v").info])
}
expect {
    Dict.from_list([("file", ["f.txt"])])
        == Cliff.tokenise(
            ["--file=f.txt"],
            [
                Opt.Spec.value("file").short("f").info,
            ])?.opts
}
