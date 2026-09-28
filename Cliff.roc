Cliff :: {}.{
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

            short : Spec(a), Str -> Spec(a)
            short = |spec, s| { ..spec, info: { ..spec.info, short: s } }

            help : Spec(a), Str -> Spec(a)
            help = |spec, s| { ..spec, info: { ..spec.info, help: s } }
        }

        TokenError : [
            UnknownOption(Str),
            MissingValue(Str),
            UnexpectedValue(Str),
            RepeatedOption(Str),
        ]
        tokenise : List(Str), List(Info) -> Try(Dict(Str, List(Str)), TokenError)
        tokenise = |argv, infos| {
            dbg (argv, infos)
            infos_by_name = infos.map(|i| (i.long, i))
                .concat(infos.drop_if(|i| i.short.is_empty()).map(|i| (i.short, i)))
                .fold_try(Dict.empty(), |d, (k, v)|
                    if d.contains(k)
                        Err(RepeatedOption(k))
                    else
                        Ok(d.insert(k, v)))?
            argv.fold_try(Dict.empty(), |opts, arg|
                if arg.starts_with("--")
                    Ok(opts.update(arg.drop_prefix("--"), |old_value|
                        match old_value {
                            Err(Missing) => Ok([""])
                            Ok(vs) => Ok(vs.append(""))
                        }))
                else if arg.starts_with("-")
                    match infos_by_name.get(arg.drop_prefix("-")) {
                        Err(KeyNotFound) => Err(UnknownOption(arg))
                        Ok(info) =>
                            Ok(opts.update(info.long, |old_value|
                                match old_value {
                                    Err(Missing) => Ok([""])
                                    Ok(vs) => Ok(vs.append(""))
                                }))
                    }
                else
                    Ok(opts))
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
    == Opt.tokenise(["--verbosity"], [Opt.Spec.count("verbosity").short("v").info])?
expect Dict.from_list([("verbosity", [""])])
    == Opt.tokenise(["-v"], [Opt.Spec.count("verbosity").short("v").info])?
