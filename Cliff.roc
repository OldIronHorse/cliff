Cliff := {}.{
    Raw : { opts: Dict(Str, List(Str)), params: Dict(Str, List(Str)) }

    TokenError : [
        UnknownOption(Str),
        MissingValue(Str),
        UnexpectedValue(Str),
        RepeatedOption(Str),
        TrailingParameters(List(Str)),
        VariadicParamNotLast(Str),
    ]

    add_opt : Raw, Cliff.Opt.Info, Try(Str, [NoValue]) -> Try(Raw, _)
    add_opt = |raw, info, maybe_value|
        match (info.kind, maybe_value) {
            (Value, Err(NoValue)) | (Values, Err(NoValue)) => Err(MissingValue(info.long))
            (Value, Ok(_)) if raw.opts.contains(info.long) => Err(RepeatedOption(info.long))
            (Value, Ok(v)) => Ok({ ..raw, opts: raw.opts.insert(info.long, [v]) })
            (Values, Ok(v)) => Ok({ ..raw, opts: upsert(raw.opts, info.long, v) })
            (_, Ok(_)) => Err(UnexpectedValue(info.long))
            (_, Err(NoValue)) => Ok({ ..raw, opts: upsert(raw.opts, info.long, "") })
        }

    add_param : Raw, Cliff.Param.Info, Str -> Raw
    add_param = |raw, info, value|
        match info.kind {
            Value => { ..raw, params: raw.params.insert(info.name, [value]) }
            Values => { ..raw, params: upsert(raw.params, info.name, value) }
        }

    get_opt_info : Dict(Str, Cliff.Opt.Info), Str -> Try(Cliff.Opt.Info, _)
    get_opt_info = |infos, name|
        match infos.get(name) {
            Ok(info) => Ok(info)
            _ => Err(UnknownOption(name))
        }

    tokenise : List(Str), List(Cliff.Opt.Info), List(Cliff.Param.Info) -> Try(Raw, TokenError)
    tokenise = |argv, opt_infos, param_infos| {
        opt_infos_by_name = opt_infos.map(|i| (i.long, i))
            .concat(opt_infos.drop_if(|i| i.short.is_empty()).map(|i| (i.short, i)))
            .fold_try(Dict.empty(), |d, (k, v)|
                if d.contains(k)
                    Err(RepeatedOption(k))
                else
                    Ok(d.insert(k, v)))?

        do = |args, p_infos, raw|
            match args {
                [] => Ok(raw)
                [opt, .. as rest] if opt.starts_with("--") =>
                    match opt.drop_prefix("--").split_first("=") {
                        Ok({ before, after }) => {
                            do(rest, p_infos, add_opt(raw, get_opt_info(opt_infos_by_name, before)?, Ok(after))?)
                        }
                        Err(NotFound) => {
                            match get_opt_info(opt_infos_by_name, opt.drop_prefix("--"))? {
                                i if i.kind == Value or i.kind == Values =>
                                    match rest {
                                        [value, .. as rest1] =>
                                            do(rest1, p_infos, add_opt(raw, i, Ok(value))?)
                                        _ => Err(MissingValue(i.long))
                                    }
                                i => do(rest, p_infos, add_opt(raw, i, Err(NoValue))?)
                            }
                        }
                    }
                [opt, .. as rest] if opt.starts_with("-") =>
                    do(rest, p_infos, opt.drop_prefix("-")
                        .to_utf8()
                        .fold_try(raw, |r, c|
                            match Str.from_utf8([c]) {
                                Ok(s) =>
                                    add_opt(r, get_opt_info(opt_infos_by_name, s)?, Err(NoValue))
                                _ => Err(UnexpectedValue(opt))
                            })?)
                [param, .. as rest] =>
                    match p_infos {
                        [pi, .. as rpi] if pi.kind == Value => do(rest, rpi, add_param(raw, pi, param))
                        [pi] if pi.kind == Values => do(rest, p_infos, add_param(raw, pi, param))
                        [pi, ..] => Err(VariadicParamNotLast(pi.name))
                        [] => Err(TrailingParameters(args))
                    }
            }

        do(argv, param_infos, { opts: Dict.empty(), params: Dict.empty() })
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

            values : Str -> Spec(Str)
            values = |long| Spec.{ info: Info.{ kind: Values, long }, convert: dummy }

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
            value : Str -> Spec(Str)
            value = |name| Spec.{ info: Info.{ name, kind: Value }, convert: dummy }

            values : Str -> Spec(List(Str))
            values = |name| Spec.{ info: Info.{ name, kind: Values }, convert: dummy}

            help : Spec, Str -> Spec
            help = |spec, s| { ..spec, info: { ..spec.info, help: s }}
        }
    }
}

upsert : Dict(a, List(b)), a, b -> Dict(a, List(b))
    where [a.is_eq : a, a -> Bool, a.to_hash : a, Hasher -> Hasher]
upsert = |d, k, v|
    d.update(k, |ov|
        match ov {
            Ok(vs) => Ok(vs.append(v))
            Err(Missing) => Ok([v])
        })

dummy : List(Str) -> Try(a, [TypeMismatch, NotFound])
dummy = |_| Err(NotFound)

expect
    Cliff.Opt.Info.{ kind: Count, short: "v", long: "verbosity", help: "verbosity level" }
        == Opt.Spec.count("verbosity").short("v").help("verbosity level").info
expect
    Cliff.Param.Info.{ kind: Value, name: "file", help: "the file to load" }
        == Param.Spec.value("file").help("the file to load").info

expect Dict.from_list([("verbosity", [""])])
    == Cliff.tokenise(["--verbosity"], [Opt.Spec.count("verbosity").short("v").info], [])?.opts
expect Dict.from_list([("verbosity", [""])])
    == Cliff.tokenise(["-v"], [Opt.Spec.count("verbosity").short("v").info], [])?.opts
expect Dict.from_list([("verbosity", ["", ""])])
    == Cliff.tokenise(["-v", "-v"], [Opt.Spec.count("verbosity").short("v").info], [])?.opts
expect Dict.from_list([("verbosity", ["", "", ""])])
    == Cliff.tokenise(["-vvv"], [Opt.Spec.count("verbosity").short("v").info], [])?.opts
expect Dict.from_list([("verbosity", [""]), ("exclusive", [""])])
    == Cliff.tokenise(
        ["-v", "-x"],
        [
            Opt.Spec.count("verbosity").short("v").info,
            Opt.Spec.count("exclusive").short("x").info,
        ],
        [])?.opts
expect Dict.from_list([("verbosity", [""]), ("exclusive", [""])])
    == Cliff.tokenise(
        ["--verbosity", "--exclusive"],
        [
            Opt.Spec.count("verbosity").info,
            Opt.Spec.flag("exclusive").info,
        ],
        [])?.opts
expect Dict.from_list([("verbosity", ["", ""]), ("exclusive", [""])])
    == Cliff.tokenise(
        ["-vxv"],
        [
            Opt.Spec.count("verbosity").short("v").info,
            Opt.Spec.count("exclusive").short("x").info,
        ],
        [])?.opts
expect Dict.from_list([("verbosity", ["", ""]), ("exclusive", ["", ""])])
    == Cliff.tokenise(
        ["-vxv", "-x"],
        [
            Opt.Spec.count("verbosity").short("v").info,
            Opt.Spec.count("exclusive").short("x").info,
        ],
        [])?.opts
expect {
    Err(UnexpectedValue("verbosity"))
        == Cliff.tokenise(["--verbosity=3"], [Opt.Spec.count("verbosity").info], [])
}
expect Err(UnknownOption("x"))
    == Cliff.tokenise(["-x"], [Opt.Spec.count("verbosity").short("v").info], [])
expect {
    Err(UnknownOption("excl"))
        == Cliff.tokenise(["--excl"], [Opt.Spec.count("verbosity").short("v").info], [])
}
expect {
    Dict.from_list([("file", ["f.txt"])])
        == Cliff.tokenise(
            ["--file=f.txt"],
            [
                Opt.Spec.value("file").short("f").info,
            ],
            [])?.opts
}
expect {
    Dict.from_list([("file", ["f.txt"])])
        == Cliff.tokenise(
            ["--file", "f.txt"],
            [
                Opt.Spec.value("file").short("f").info,
            ],
            [])?.opts
}
expect {
    Dict.from_list([("file", ["f.txt", "g.txt"])])
        == Cliff.tokenise(
            ["--file", "f.txt", "--file=g.txt"],
            [
                Opt.Spec.values("file").info,
            ],
            [])?.opts
}
expect {
    Dict.from_list([("offset", ["-5"])])
        == Cliff.tokenise(
            ["--offset", "-5"],
            [
                Opt.Spec.value("offset").info,
            ],
            [])?.opts
}

expect Dict.from_list([("file", ["f.txt"])])
    == Cliff.tokenise(
        ["f.txt"],
        [],
        [
            Param.Spec.value("file").info,
        ])?.params
expect {
        params: Dict.from_list([("files", ["f.txt", "g.txt"]), ("expr", ["error"])]),
        opts: Dict.from_list([("invert", [""])])
    } == Cliff.tokenise(
        ["-v", "error", "f.txt", "g.txt"],
        [
            Opt.Spec.flag("invert").short("v").info,
        ],
        [
            Param.Spec.value("expr").info,
            Param.Spec.values("files").info,
        ])?
expect {
    Err(VariadicParamNotLast("files")) == Cliff.tokenise(
        ["-v", "error", "f.txt", "g.txt"],
        [
            Opt.Spec.flag("invert").short("v").info,
        ],
        [
            Param.Spec.values("files").info,
            Param.Spec.value("expr").info,
        ])
}
