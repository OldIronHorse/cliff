Cliff := {}.{
    Cli(a) := {
        opt_infos: List(Cliff.Opt.Info),
        param_infos: List(Cliff.Param.Info),
        assemble: Cliff.Raw -> Try(a, AssembleError),
    }.{
        parse : Cli(a), List(Str) -> Try(a, _)
        parse = |cli, argv|
            tokenise(argv, cli.opt_infos, cli.param_infos)?
                |> cli.assemble
                |> Try.map_err(|e| e)
    }

    succeed : a -> Cli(a)
    succeed = |value| Cli.{ opt_infos: [], param_infos: [], assemble: |_| Ok(value) }

    AssembleError(errs) : [
        InvalidOptValue(Str, List(Str)),
        InvalidParamValue(Str, List(Str)),
        ..errs
    ]

    Optional(a) : [Some(a), None]

    with_opt : Cli(a -> b) , Cliff.Opt.Spec(a) -> Cli(b)
    with_opt = |cli, spec|
        Cli.{
            opt_infos: cli.opt_infos.append(spec.info),
            param_infos: cli.param_infos,
            assemble: |raw| {
                f = (cli.assemble)(raw)?
                vs = raw.opts.get(spec.info.long).ok_or([])
                match (spec.convert)(vs) {
                    Ok(v) => Ok(f(v))
                    Err(NotFound) => { crash "unreachable #1" }
                    Err(TypeMismatch) => Err(InvalidOptValue(spec.info.long, vs))
                }
            }
        }

    with_param : Cli(a -> b) , Cliff.Param.Spec(a) -> Cli(b)
    with_param = |cli, spec|
        Cli.{
            opt_infos: cli.opt_infos,
            param_infos: cli.param_infos.append(spec.info),
            assemble: |raw| {
                f = (cli.assemble)(raw)?
                vs = raw.params.get(spec.info.name).ok_or([])
                match (spec.convert)(vs) {
                    Ok(v) => Ok(f(v))
                    Err(NotFound) => { crash "unreachable #2" }
                    Err(TypeMismatch) => Err(InvalidParamValue(spec.info.name, vs))
                }
            }
        }

    Raw : { opts: Dict(Str, List(Str)), params: Dict(Str, List(Str)) }

    TokenError(errs) : [
        UnknownOption(Str),
        MissingValue(Str),
        UnexpectedValue(Str),
        RepeatedOption(Str),
        TrailingParameters(List(Str)),
        VariadicParamNotLast(Str),
        MissingArguments(List(Str)),
        MandatoryParamAfterOptional(Str),
        ..errs
    ]

    add_opt : Raw, Cliff.Opt.Info, Optional(Str) -> Try(Raw, _)
    add_opt = |raw, info, maybe_value|
        match (info.kind, maybe_value) {
            (Value, None) | (Values, None) => Err(MissingValue(info.long))
            (Value, Some(_)) if raw.opts.contains(info.long) => Err(RepeatedOption(info.long))
            (Value, Some(v)) => Ok({ ..raw, opts: raw.opts.insert(info.long, [v]) })
            (Values, Some(v)) => Ok({ ..raw, opts: upsert(raw.opts, info.long, v) })
            (_, Some(_)) => Err(UnexpectedValue(info.long))
            (_, None) => Ok({ ..raw, opts: upsert(raw.opts, info.long, "") })
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
        _ = param_infos.fold_try(Bool.False, |seen_optional, p|
            if p.mandatory and seen_optional
                Err(MandatoryParamAfterOptional(p.name))
            else
                Ok(p.mandatory.not())
        )?

        opt_infos_by_name = opt_infos.map(|i| (i.long, i))
            .concat(opt_infos.drop_if(|i| i.short.is_empty()).map(|i| (i.short, i)))
            .fold_try(Dict.empty(), |d, (k, v)|
                if d.contains(k)
                    Err(RepeatedOption(k))
                else
                    Ok(d.insert(k, v)))?

        do = |args, p_infos, raw|
            match args {
                [] =>
                    match p_infos.keep_if(|i| i.mandatory) {
                        [] => Ok(raw)
                        remaining => Err(MissingArguments(remaining.map(|p| p.name)))
                    }
                [opt, .. as rest] if opt.starts_with("--") =>
                    match opt.drop_prefix("--").split_first("=") {
                        Ok({ before, after }) => {
                            do(rest, p_infos, add_opt(raw, get_opt_info(opt_infos_by_name, before)?, Some(after))?)
                        }
                        Err(NotFound) => {
                            match get_opt_info(opt_infos_by_name, opt.drop_prefix("--"))? {
                                i if i.kind == Value or i.kind == Values =>
                                    match rest {
                                        [value, .. as rest1] =>
                                            do(rest1, p_infos, add_opt(raw, i, Some(value))?)
                                        _ => Err(MissingValue(i.long))
                                    }
                                i => do(rest, p_infos, add_opt(raw, i, None)?)
                            }
                        }
                    }
                [opt, .. as rest] if opt.starts_with("-") =>
                    do(rest, p_infos, opt.drop_prefix("-")
                        .to_utf8()
                        .fold_try(raw, |r, c|
                            match Str.from_utf8([c]) {
                                Ok(s) =>
                                    add_opt(r, get_opt_info(opt_infos_by_name, s)?, None)
                                _ => Err(UnexpectedValue(opt))
                            })?)
                [param, .. as rest] =>
                    match p_infos {
                        [pi] if pi.kind == Values =>
                            do(rest, [{ ..pi, mandatory: Bool.False }], add_param(raw, pi, param))
                        [pi, .. as rpi] if pi.kind == Value => do(rest, rpi, add_param(raw, pi, param))
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
            count : Str -> Spec(U64)
            count = |long| Spec.{ info: Info.{ kind: Count, long }, convert: convert_count }

            flag : Str -> Spec(Bool)
            flag = |long| Spec.{ info: Info.{ kind: Flag, long }, convert: convert_flag }

            value : Str -> Spec(Optional(Str))
            value = |long| Spec.{ info: Info.{ kind: Value, long }, convert: convert_optional_value }

            one_of : Str, List((Str, a)) -> Spec(Optional(a))
            one_of = |long, options|
                Spec.{
                    info: Info.{ kind: Value, long },
                    convert: convert_one_of(Dict.from_list(options))
                }

            values : Str -> Spec(List(Str))
            values = |long| Spec.{ info: Info.{ kind: Values, long }, convert: convert_values}

            short : Spec(a), Str -> Spec(a)
            short = |spec, s| { ..spec, info: { ..spec.info, short: s } }

            integer : Spec(Optional(Str)) -> Spec(Optional(I64))
            integer = |spec| {
                info: spec.info,
                convert: to_optional_integer(spec.convert)
            }

            default : Spec(Optional(a)), a -> Spec(a)
            default = |spec, def| {
                info: spec.info,
                convert: with_default(spec.convert, def)
            }

            help : Spec(a), Str -> Spec(a)
            help = |spec, s| { ..spec, info: { ..spec.info, help: s } }
        }
    }
    Param := {}.{
        Kind : [Value, Values]
        Info := { kind: Kind, name: Str, mandatory: Bool ?? Bool.True,  help: Str ?? "" }.{
            is_eq = |self, other|
                self.kind == other.kind
                    and self.name == other.name
                    and self.mandatory == other.mandatory
                    and self.help == other.help
        }
        Spec(a) := { info: Info, convert: List(Str) -> Try(a, [TypeMismatch, NotFound])}.{
            value : Str -> Spec(Str)
            value = |name| Spec.{ info: Info.{ name, kind: Value }, convert: convert_value }

            values : Str -> Spec(List(Str))
            values = |name| Spec.{ info: Info.{ name, kind: Values }, convert: convert_values}

            integer : Spec(Str) -> Spec(I64)
            integer = |spec| {
                info: spec.info,
                convert: to_integer(spec.convert)
            }

            optionals : Spec(List(a)) -> Spec(List(a))
            optionals = |spec| { ..spec, info: { ..spec.info, mandatory: Bool.False } }

            optional : Spec(a) -> Spec(Optional(a))
            optional = |spec| {
                info: { ..spec.info, mandatory: Bool.False },
                convert: make_optional(spec.convert),
            }

            default : Spec(Optional(a)), a -> Spec(a)
            default = |spec, def| {
                info: spec.info,
                convert: with_default(spec.convert, def)
            }

            help : Spec, Str -> Spec
            help = |spec, s| { ..spec, info: { ..spec.info, help: s }}
        }
    }
}

to_integer : (List(Str) -> Try(Str, [TypeMismatch, NotFound]))
   -> (List(Str) -> Try(I64, [TypeMismatch, NotFound]))
to_integer = |converter|
    |ov|
        match converter(ov)? |> I64.from_str() {
            Ok(n) => Ok(n)
            Err(_) => Err(TypeMismatch)
        }

to_optional_integer : (List(Str) -> Try(Optional(Str), [TypeMismatch, NotFound]))
   -> (List(Str) -> Try(Optional(I64), [TypeMismatch, NotFound]))
to_optional_integer = |converter|
    |ov| match converter(ov)? {
        None => Ok(None)
        Some(v) =>
            match I64.from_str(v) {
                Ok(n) => Ok(Some(n))
                Err(_) => Err(TypeMismatch)
            }
    }

with_default : (List(Str) -> Try(Optional(a), e)), a -> (List(Str) -> Try(a, e))
with_default = |converter, def|
    |ov| match converter(ov) {
        Ok(None) => Ok(def)
        Ok(Some(v)) => Ok(v)
        Err(e) => Err(e)
    }

make_optional : (List(Str) -> Try(a, [TypeMismatch, NotFound]))
    -> (List(Str) -> Try(Optional(a), [TypeMismatch, NotFound]))
make_optional = |converter|
    |v| match converter(v) {
        Ok(s) => Ok(Some(s))
        Err(NotFound) => Ok(None)
        Err(e) => Err(e)
    }

expect {
    cli = Cliff.succeed(|verbosity| |file| { verbosity, file })
        |> Cliff.with_opt(Opt.Spec.value("verbosity").integer())
        |> Cliff.with_opt(Opt.Spec.value("file"))
    Err(InvalidOptValue("verbosity", ["two"])) == cli.parse(["--verbosity", "two"])
}

expect {
    cli = Cliff.succeed(|verbosity| |file| { verbosity, file })
        |> Cliff.with_opt(Opt.Spec.value("verbosity").integer().default(56))
        |> Cliff.with_opt(Opt.Spec.value("file"))
    { verbosity: 56, file: None } == cli.parse([])?
}

expect {
    cli = Cliff.succeed(|verbosity| |length| { verbosity, length })
        |> Cliff.with_opt(Opt.Spec.count("verbosity"))
        |> Cliff.with_param(Param.Spec.value("length").integer())
    { verbosity: 0, length: 32 } == cli.parse(["32"])?
}

expect {
    cli = Cliff.succeed(|verbosity| |length| { verbosity, length })
        |> Cliff.with_opt(Opt.Spec.count("verbosity"))
        |> Cliff.with_param(Param.Spec.value("length").integer())
    Err(InvalidParamValue("length", ["two"])) == cli.parse(["two"])
}

expect {
    cli = Cliff.succeed(|verbosity| |file| { verbosity, file })
        |> Cliff.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cliff.with_opt(Opt.Spec.value("file"))
    { verbosity: 1, file: Some("f.txt") } == cli.parse(["-v", "--file", "f.txt"])?
}

expect {
    cli = Cliff.succeed(|verbosity| |file| { verbosity, file })
        |> Cliff.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cliff.with_opt(Opt.Spec.value("file"))
    { verbosity: 0, file: Some("f.txt") } == cli.parse(["--file", "f.txt"])?
}

expect {
    cli = Cliff.succeed(|verbosity| |file| { verbosity, file })
        |> Cliff.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cliff.with_opt(Opt.Spec.value("file").default("d.txt"))
    { verbosity: 0, file: "d.txt" } == cli.parse([])?
}

expect {
    cli = Cliff.succeed(|verbosity| |file| { verbosity, file })
        |> Cliff.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cliff.with_opt(Opt.Spec.value("file"))
    { verbosity: 0, file: None } == cli.parse([])?
}

expect {
    cli = Cliff.succeed(|verbosity| |file| { verbosity, file })
        |> Cliff.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cliff.with_param(Param.Spec.value("file"))
    { verbosity: 1, file: "f.txt" } == cli.parse(["-v", "f.txt"])?
}

expect {
    cli = Cliff.succeed(|verbosity| |file| { verbosity, file })
        |> Cliff.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cliff.with_param(Param.Spec.value("file"))
    Err(MissingArguments(["file"])) == cli.parse(["-v"])
}

expect {
    cli = Cliff.succeed(|verbosity| |files| { verbosity, files })
        |> Cliff.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cliff.with_param(Param.Spec.values("files"))
    Err(MissingArguments(["files"])) == cli.parse(["-v"])
}

expect {
    cli = Cliff.succeed(|verbosity| |files| { verbosity, files })
        |> Cliff.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cliff.with_param(Param.Spec.values("files").optionals())
    { verbosity: 1, files: [] } == cli.parse(["-v"])?
}

expect {
    cli = Cliff.succeed(|verbosity| |files| { verbosity, files })
        |> Cliff.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cliff.with_param(Param.Spec.values("files").optionals())
    { verbosity: 1, files: ["a.txt", "b.txt"] } == cli.parse(["-v", "a.txt", "b.txt"])?
}

expect {
    cli = Cliff.succeed(|verbosity| |file| { verbosity, file })
        |> Cliff.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cliff.with_param(Param.Spec.value("file").optional())
    { verbosity: 1, file: None } == cli.parse(["-v"])?
}

expect {
    cli = Cliff.succeed(|verbosity| |file| { verbosity, file })
        |> Cliff.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cliff.with_param(Param.Spec.value("file").optional().default("def.txt"))
    { verbosity: 1, file: "def.txt" } == cli.parse(["-v"])?
}

expect {
    cli = Cliff.succeed(|verbosity| |file| { verbosity, file })
        |> Cliff.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cliff.with_param(Param.Spec.value("file").optional())
    { verbosity: 1, file: Some("f.txt") } == cli.parse(["-v", "f.txt"])?
}

expect {
    cli = Cliff.succeed(|verbosity| |file| { verbosity, file })
        |> Cliff.with_opt(Opt.Spec.one_of("verbosity",[("l", Low), ("m", Medium), ("h", High)]))
        |> Cliff.with_param(Param.Spec.value("file").optional().default("def.txt"))
    { verbosity: Some(Low), file: "f.txt" } == cli.parse(["--verbosity", "l", "f.txt"])?
}

expect {
    cli = Cliff.succeed(|verbosity| |file| { verbosity, file })
        |> Cliff.with_opt(Opt.Spec.one_of("verbosity",[("l", Low), ("m", Medium), ("h", High)]))
        |> Cliff.with_param(Param.Spec.value("file").optional().default("def.txt"))
    Err(InvalidOptValue("verbosity", ["low"])) == cli.parse(["--verbosity", "low", "f.txt"])
}

expect {
    cli = Cliff.succeed(|verbosity| |file|{ verbosity, file })
        |> Cliff.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cliff.with_param(Param.Spec.value("file"))
    { verbosity: 1, file: "f.txt" } == cli.parse(["-v", "f.txt"])?
}

upsert : Dict(a, List(b)), a, b -> Dict(a, List(b))
    where [a.is_eq : a, a -> Bool, a.to_hash : a, Hasher -> Hasher]
upsert = |d, k, v|
    d.update(k, |ov|
        match ov {
            Ok(vs) => Ok(vs.append(v))
            Err(Missing) => Ok([v])
        })

convert_flag: List(Str) -> Try(Bool, [TypeMismatch, NotFound])
convert_flag = |vs|
    match vs {
        [] => Ok(Bool.False)
        _ => Ok(Bool.True)
    }

convert_optional_value: List(Str) -> Try(Optional(Str), [TypeMismatch, NotFound])
convert_optional_value = |vs|
    match vs {
        [] => Ok(None)
        [v, ..] => Ok(Some(v))
    }

convert_value: List(Str) -> Try(Str, [TypeMismatch, NotFound])
convert_value = |vs|
    match vs {
        [] => Err(NotFound)
        [v, ..] => Ok(v)
    }

convert_values: List(Str) -> Try(List(Str), [TypeMismatch, NotFound])
convert_values = |vs| Ok(vs)

convert_count: List(Str) -> Try(U64, [TypeMismatch, NotFound])
convert_count = |vs| Ok(vs.len())

convert_one_of : Dict(Str, a) -> (List(Str) -> Try(Optional(a), [TypeMismatch, NotFound]))
convert_one_of = |lookup| |vs|
    match vs {
        [] => Ok(None)
        [v, ..] => lookup.get(v).map_both(|value| Some(value), |_| TypeMismatch)
    }

expect Some(5) == convert_one_of(Dict.from_list([("one", 1), ("five", 5), ("seven", 7)]))(["five"])?
expect Err(TypeMismatch) == convert_one_of(Dict.from_list([("one", 1), ("five", 5), ("seven", 7)]))(["six"])

expect Bool.True == convert_flag([""])?
expect Bool.False == convert_flag([])?

expect Err(NotFound) == convert_value([])
expect "a" == convert_value(["a"])?

expect 0 == convert_count([])?
expect 1 == convert_count([""])?
expect 5 == convert_count(["", "", "", "", ""])?

expect [] == convert_values([])?
expect ["one"]== convert_values(["one"])?
expect ["one", "2", "three", "4", "five"] == convert_values(["one", "2", "three", "4", "five"])?

expect {
    expr_spec = Param.Spec.value("expr")
    "one" == Cliff.tokenise(["one"], [], [expr_spec.info])?
        .params.get(expr_spec.info.name).ok_or([])
        |> (expr_spec.convert)()?
}
expect {
    expr_spec = Param.Spec.values("expr")
    ["one", "two", "3"] == Cliff.tokenise(["one", "two", "3"], [], [expr_spec.info])?
        .params.get(expr_spec.info.name).ok_or([])
        |> (expr_spec.convert)()?
}
expect {
    expr_spec = Opt.Spec.values("expr").short("x")
    ["one", "two", "3"] == Cliff.tokenise(["--expr", "one", "--expr=two", "--expr", "3"], [expr_spec.info], [])?
        .opts.get(expr_spec.info.long).ok_or([])
        |> (expr_spec.convert)()?
}
expect {
    expr_spec = Opt.Spec.count("expr").short("x")
    0 == Cliff.tokenise([], [expr_spec.info], [])?
        .opts.get(expr_spec.info.long).ok_or([])
        |> (expr_spec.convert)()?
}
expect {
    expr_spec = Opt.Spec.count("expr").short("x")
    5 == Cliff.tokenise(["-xxxxx"], [expr_spec.info], [])?
        .opts.get(expr_spec.info.long).ok_or([])
        |> (expr_spec.convert)()?
}
expect {
    expr_spec = Opt.Spec.value("expr").short("x")
    None == Cliff.tokenise([], [expr_spec.info], [])?
        .opts.get(expr_spec.info.long).ok_or([])
        |> (expr_spec.convert)()?
}
expect {
    expr_spec = Opt.Spec.value("expr")
    Some("some expression") == Cliff.tokenise(["--expr", "some expression"], [expr_spec.info], [])?
        .opts.get(expr_spec.info.long).ok_or([])
        |> (expr_spec.convert)()?
}
expect {
    quiet_spec = Opt.Spec.flag("quiet").short("q")
    (quiet_spec.convert)(Cliff.tokenise([], [quiet_spec.info], [])?.opts.get(quiet_spec.info.long).ok_or([]))?.not()
}
expect {
    quiet_spec = Opt.Spec.flag("quiet").short("q")
    (quiet_spec.convert)(Cliff.tokenise(["-q"], [quiet_spec.info], [])?.opts.get(quiet_spec.info.long).ok_or([]))?
}

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
        params: Dict.from_list([("files", ["f.txt", "g.txt"]), ("expr", ["error"])]),
        opts: Dict.from_list([("invert", [""])])
    } == Cliff.tokenise(
        ["-v", "error", "f.txt", "g.txt"],
        [
            Opt.Spec.flag("invert").short("v").info,
        ],
        [
            Param.Spec.value("expr").info,
            Param.Spec.values("files").optional().info,
        ])?
expect {
    Err(MissingArguments(["files"])) == Cliff.tokenise(
        ["-v", "error"],
        [
            Opt.Spec.flag("invert").short("v").info,
        ],
        [
            Param.Spec.value("expr").info,
            Param.Spec.values("files").info,
        ])
}
expect {
        params: Dict.from_list([("expr", ["error"])]),
        opts: Dict.from_list([("invert", [""])])
    } == Cliff.tokenise(
        ["-v", "error"],
        [
            Opt.Spec.flag("invert").short("v").info,
        ],
        [
            Param.Spec.value("expr").info,
            Param.Spec.values("files").optional().info,
        ])?
expect {
    Err(MandatoryParamAfterOptional("files")) == Cliff.tokenise(
        ["-v", "error", "f.txt", "g.txt"],
        [
            Opt.Spec.flag("invert").short("v").info,
        ],
        [
            Param.Spec.value("expr").optional().info,
            Param.Spec.values("files").info,
        ])
}
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
