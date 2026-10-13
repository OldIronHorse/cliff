Cli(a) := {
    opt_infos: List(Cli.Opt.Info),
    param_infos: List(Cli.Param.Info),
    assemble: Cli.Raw -> Try(a, CliError),
    usage: Str,
    sections : Dict(U64, Str),
    coda: Str,
    commands: List({ name: Str, help: Str }),
}.{
    parse : Cli(a), List(Str) -> Try(a, _)
    parse = |cli, argv|
        match tokenise(argv, cli.opt_infos, cli.param_infos) {
            Ok(ts) => (cli.assemble)(ts)
            Err(RenderHelp) => Err(ShowHelp(cli.to_help_str()))
            Err(e) => Err(e)
        }

    to_help_str : Cli(a) -> Str
    to_help_str = |self| {
        opt_descs = self.opt_infos.map(|i| i.to_help_str())
        max_opt_len = opt_descs
            .map(|(opts, _)| opts.count_utf8_bytes())
            .max()
            .ok_or(0)
            .max(self.commands.map(|c| c.name.count_utf8_bytes()).max().ok_or(0))
            .max(10)
        (if self.usage.is_empty() [] else [self.usage])
            .concat(if opt_descs.is_empty() [] else [""])
            .concat(opt_descs
                .map_with_index(|(opts, desc), i|
                    [
                        match self.sections.get(i) {
                            Ok(heading) => "\n${heading}\n"
                            _ => ""
                        },
                        opts, " ".repeat(max_opt_len + 2 - opts.count_utf8_bytes()), desc
                    ]
                    |> Str.join_with("")))
            .concat(if self.commands.is_empty() [] else [""])
            .concat(self.commands.map(|c| "  ${c.name}${" ".repeat(max_opt_len - c.name.count_utf8_bytes())}${c.help}"))
            .append("\n${help_option}${" ".repeat(max_opt_len - help_option.count_utf8_bytes() + 2)}display this help text and exit")
            .concat(if self.coda.is_empty() [] else ["\n${self.coda}"])
            |> Str.join_with("\n")
    }

    succeed : a -> Cli(a)
    succeed = |value| Cli.{
        opt_infos: [],
        param_infos: [],
        assemble: |_| Ok(value),
        sections: Dict.empty(),
        usage: "",
        coda: "",
        commands: [],
    }

    with_usage : Cli(a), Str -> Cli(a)
    with_usage = |cli, usage| { ..cli, usage }

    with_coda : Cli(a), Str -> Cli(a)
    with_coda = |cli, coda| { ..cli, coda }

    with_opt_help_section : Cli(a), Str -> Cli(a)
    with_opt_help_section  = |cli, text|
        { ..cli, sections: cli.sections.insert(cli.opt_infos.len(), text) }

    with_opt_group : Cli(a -> b), List((Cli.Opt.Spec(Bool), a)), a -> Cli(b)
    with_opt_group = |cli, specs, default|
        Cli.{
            sections: cli.sections,
            usage: cli.usage,
            coda: cli.coda,
            opt_infos: cli.opt_infos.concat(specs.map(|(spec, _)| spec.info)),
            param_infos: cli.param_infos,
            assemble: |raw| {
                f = (cli.assemble)(raw)?
                match specs
                    .keep_oks(|(spec, value)| raw.opts.get(spec.info.long).map_ok(|_| (spec, value))) {
                        [] => Ok(f(default))
                        [(_, v)] => Ok(f(v))
                        vs => Err(ConflictingOpts(vs.map(|(s, _)| s.info.long)))
                }
            },
            commands: cli.commands,
        }

    with_opt : Cli(a -> b) , Cli.Opt.Spec(a) -> Cli(b)
    with_opt = |cli, spec|
        Cli.{
            sections: cli.sections,
            usage: cli.usage,
            coda: cli.coda,
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
            },
            commands: cli.commands,
        }

    with_param : Cli(a -> b) , Cli.Param.Spec(a) -> Cli(b)
    with_param = |cli, spec|
        Cli.{
            sections: cli.sections,
            usage: cli.usage,
            coda: cli.coda,
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
            },
            commands: cli.commands,
        }

    Subcommand(a) := {
        name: Str,
        help: Str ?? "",
        cli: Cli(a),
    }.{
        command : Str, Cli(a) -> Subcommand(a)
        command = |name, cli| Subcommand.{ name, cli }

        help : Subcommand(a),  Str -> Subcommand(a)
        help = |cmd, text| { ..cmd, help: text }
    }

    with_subcommands : Cli(a -> b), List(Subcommand(a)) -> Cli(b)
    with_subcommands = |cli, sub_cmds|
        Cli.{
            sections: cli.sections,
            usage: cli.usage,
            coda: cli.coda,
            opt_infos: cli.opt_infos,
            param_infos: cli.param_infos.append(Cli.Param.Info.{ kind: Command, name: "", mandatory: False }),
            assemble: |raw| {
                f = (cli.assemble)(raw)?
                match raw.params.to_list() {
                    [(name, argv)] =>
                        match sub_cmds.find_first(|cmd| cmd.name == name) {
                            Ok(sub) => Ok(f(sub.cli.parse(argv)?))
                            Err(NotFound) => Err(UnknownSubcommand(name))
                        }
                    [] => Err(MissingSubcommand)
                    _ => Err(TrailingParameters(raw.params.keys()))
                }
            },
            commands: sub_cmds.map(|c| { name: c.name, help: c.help })
        }

    map : Cli(a), (a -> b) -> Cli(b)
    map = |cli, fn|
        Cli.{
            sections: cli.sections,
            usage: cli.usage,
            coda: cli.coda,
            opt_infos: cli.opt_infos,
            param_infos: cli.param_infos,
            assemble: |raw| Ok(fn((cli.assemble)(raw)?)),
            commands: cli.commands,
            }

    Optional(a) : [Some(a), None]

    Raw : { opts: Dict(Str, List(Str)), params: Dict(Str, List(Str)) }

    CliError : [
        UnknownOption(Str),
        MissingValue(Str),
        UnexpectedValue(Str),
        RepeatedOption(Str),
        TrailingParameters(List(Str)),
        VariadicParamNotLast(Str),
        MissingArguments(List(Str)),
        MandatoryParamAfterOptional(Str),
        ShowHelp(Str),
        RenderHelp,
        InvalidOptValue(Str, List(Str)),
        InvalidParamValue(Str, List(Str)),
        ConflictingOpts(List(Str)),
        UnknownSubcommand(Str),
        MissingSubcommand,
        SubcommandNotLast,
        MultipleSubcommandGroups,
    ]

    Opt := {}.{
        Kind : [Flag, Count, Value, Values]
        Info := { kind: Kind, long: Str, short: Str ?? "", help: Str ?? "", symbol: Str ?? ""}.{
            is_eq = |self, other|
                self.kind == other.kind
                    and self.short == other.short
                    and self.long == other.long
                    and self.help == other.help
                    and self.symbol == other.symbol

            to_help_str = |self| {
                short = match self.short {
                    "" => "    "
                    s => "-${s}, "
                }
                long = match self.kind {
                    Value | Values if self.symbol.is_empty().not() => "--${self.long}=${self.symbol}"
                    _ => "--${self.long}"
                }
                ("${short}${long}", self.help)
            }
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
            help = |spec, help| { ..spec, info: { ..spec.info, help } }

            symbol : Spec(a), Str -> Spec(a)
            symbol = |spec, symbol| { ..spec, info: { ..spec.info, symbol } }
        }
    }

    Param := {}.{
        Kind : [Value, Values, Command]
        Info := { kind: Kind, name: Str, mandatory: Bool ?? Bool.True }.{
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
        }
    }
}

add_opt : Raw, Cli.Opt.Info, Optional(Str) -> Try(Raw, _)
add_opt = |raw, info, maybe_value|
    match (info.kind, maybe_value) {
        (Value, None) | (Values, None) => Err(MissingValue(info.long))
        (Value, Some(_)) if raw.opts.contains(info.long) => Err(RepeatedOption(info.long))
        (Value, Some(v)) => Ok({ ..raw, opts: raw.opts.insert(info.long, [v]) })
        (Values, Some(v)) => Ok({ ..raw, opts: upsert(raw.opts, info.long, v) })
        (_, Some(_)) => Err(UnexpectedValue(info.long))
        (_, None) => Ok({ ..raw, opts: upsert(raw.opts, info.long, "") })
    }

add_param : Raw, Cli.Param.Info, Str -> Raw
add_param = |raw, info, value|
    match info.kind {
        Value => { ..raw, params: raw.params.insert(info.name, [value]) }
        Values | Command => { ..raw, params: upsert(raw.params, info.name, value) }
    }

get_opt_info : Dict(Str, Cli.Opt.Info), Str -> Try(Cli.Opt.Info, _)
get_opt_info = |infos, name|
    match infos.get(name) {
        Ok(info) => Ok(info)
        _ if name == "help" => Err(RenderHelp)
        _ => Err(UnknownOption(name))
    }

validate_subcommands: List(Cli.Param.Info) -> Try({}, _)
validate_subcommands = |infos| {
    cmds = infos.keep_if(|i| i.kind == Command)
    match (cmds, infos.last()) {
        ([], _) => Ok({})
        ([_], Ok(i)) if i.kind == Command => Ok({})
        ([_], Ok(_)) => Err(SubcommandNotLast)
        _ => Err(MultipleSubcommandGroups)
    }
}

tokenise : List(Str), List(Cli.Opt.Info), List(Cli.Param.Info) -> Try(Raw, _)
tokenise = |argv, opt_infos, param_infos| {
    _ = validate_subcommands(param_infos)?
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

    do = |args, p_infos, raw, consider_opts|
        match args {
            [] =>
                match p_infos.keep_if(|i| i.mandatory) {
                    [] => Ok(raw)
                    remaining => Err(MissingArguments(remaining.map(|p| p.name)))
                }
            ["--", .. as rest] => do(rest, p_infos, raw, False)
            [opt, .. as rest] if consider_opts and opt.starts_with("--") =>
                match opt.drop_prefix("--").split_first("=") {
                    Ok({ before, after }) => {
                        do(rest, p_infos, add_opt(raw, get_opt_info(opt_infos_by_name, before)?, Some(after))?, consider_opts)
                    }
                    Err(NotFound) => {
                        match get_opt_info(opt_infos_by_name, opt.drop_prefix("--"))? {
                            i if i.kind == Value or i.kind == Values =>
                                match rest {
                                    [value, .. as rest1] =>
                                        do(rest1, p_infos, add_opt(raw, i, Some(value))?, consider_opts)
                                    _ => Err(MissingValue(i.long))
                                }
                            i => do(rest, p_infos, add_opt(raw, i, None)?, consider_opts)
                        }
                    }
                }
            [opt, .. as rest] if consider_opts and opt.starts_with("-") and opt.count_utf8_bytes() > 1 =>
                match opt.drop_prefix("-") {
                    #tags if tags.count_utf8_bytes() == 1 and [Value, Values].contains(get_opt_info(opt_infos_by_name, tags)?.kind) =>
                    #match (rest, get_opt_info(opt_infos_by_name, tags)?) {
                    #([value, .. as rest1], i) =>
                    #do(rest1, p_infos, add_opt(raw, i, Some(value))?)
                    #([], i) => Err(MissingValue(i.long))
                    #}
                    tags =>
                        do(rest, p_infos, tags.to_utf8()
                            .fold_try(raw, |r, c|
                                match Str.from_utf8([c]) {
                                    Ok(s) =>
                                        add_opt(r, get_opt_info(opt_infos_by_name, s)?, None)
                                    _ => Err(UnexpectedValue(opt))
                                })?, consider_opts)
                }
            [param, .. as rest] =>
                match p_infos {
                    [pi] if pi.kind == Values =>
                        do(rest,
                            [{ ..pi, mandatory: Bool.False }],
                            { ..raw, params: upsert(raw.params, pi.name, param) },
                            consider_opts)
                    [pi] if pi.kind == Command =>
                        Ok({ ..raw, params: raw.params.insert(param, rest) })
                    [pi, .. as rpi] if pi.kind == Value =>
                        do(rest,
                            rpi,
                            { ..raw, params: raw.params.insert(pi.name, [param]) },
                            consider_opts)
                    [pi, ..] => Err(VariadicParamNotLast(pi.name))
                    [] => Err(TrailingParameters(args))
                }
        }

    do(argv, param_infos, { opts: Dict.empty(), params: Dict.empty() }, True)
}

help_option = "    --help"

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
    cli = Cli.succeed(|verbosity| |speed| { verbosity, speed })
        |> Cli.with_opt_group([
            (Opt.Spec.flag("high").short("h"), High),
            (Opt.Spec.flag("med"), Medium),
            (Opt.Spec.flag("low"), Low),
        ], Low)
        |> Cli.with_opt_group([
            (Opt.Spec.flag("high").short("h"), High),
            (Opt.Spec.flag("fast"), Fast),
            (Opt.Spec.flag("faster"), Faster),
        ], Fast)
    Err(RepeatedOption("high")) == cli.parse([])
}

expect {
    cli = Cli.succeed(|verbosity| |file| { verbosity, file })
        |> Cli.with_opt_group([
            (Opt.Spec.flag("high"), High),
            (Opt.Spec.flag("med"), Medium),
            (Opt.Spec.flag("low"), Low),
        ], Low)
        |> Cli.with_opt(Opt.Spec.value("file"))
    { verbosity: Medium, file: None } == cli.parse(["--med"])?
}

expect {
    cli = Cli.succeed(|verbosity| |file| { verbosity, file })
        |> Cli.with_opt_group([
            (Opt.Spec.flag("high"), High),
            (Opt.Spec.flag("med").short("m"), Medium),
            (Opt.Spec.flag("low"), Low),
        ], Low)
        |> Cli.with_opt(Opt.Spec.value("file"))
    { verbosity: Medium, file: None } == cli.parse(["--med", "-m", "--med"])?
}

expect {
    cli = Cli.succeed(|verbosity| |file| { verbosity, file })
        |> Cli.with_opt_group([
            (Opt.Spec.flag("high"), High),
            (Opt.Spec.flag("med"), Medium),
            (Opt.Spec.flag("low"), Low),
        ], Low)
        |> Cli.with_opt(Opt.Spec.value("file"))
    { verbosity: Low, file: None } == cli.parse([])?
}

expect {
    cli = Cli.succeed(|verbosity| |file| { verbosity, file })
        |> Cli.with_opt(Opt.Spec.value("verbosity").integer())
        |> Cli.with_opt(Opt.Spec.value("file"))
    Err(InvalidOptValue("verbosity", ["two"])) == cli.parse(["--verbosity", "two"])
}

expect {
    cli = Cli.succeed(|verbosity| |file| { verbosity, file })
        |> Cli.with_opt(Opt.Spec.value("verbosity").integer().default(56))
        |> Cli.with_opt(Opt.Spec.count("file"))
        #|> Cli.with_opt(Opt.Spec.flag("file"))
    { verbosity: 56, file: 0 } == cli.parse([])?
    #{ verbosity: 56, file: False } == cli.parse([])?
}

expect {
    cli = Cli.succeed(|verbosity| |length| { verbosity, length })
        |> Cli.with_opt(Opt.Spec.count("verbosity"))
        |> Cli.with_param(Param.Spec.value("length").integer())
    { verbosity: 0, length: 32 } == cli.parse(["32"])?
}

expect {
    cli = Cli.succeed(|verbosity| |length| { verbosity, length })
        |> Cli.with_opt(Opt.Spec.count("verbosity"))
        |> Cli.with_param(Param.Spec.value("length").integer())
    Err(InvalidParamValue("length", ["two"])) == cli.parse(["two"])
}

expect {
    cli = Cli.succeed(|verbosity| |file| { verbosity, file })
        |> Cli.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cli.with_opt(Opt.Spec.value("file"))
    { verbosity: 1, file: Some("f.txt") } == cli.parse(["-v", "--file", "f.txt"])?
}

expect {
    cli = Cli.succeed(|verbosity| |file| { verbosity, file })
        |> Cli.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cli.with_opt(Opt.Spec.value("file"))
    { verbosity: 0, file: Some("f.txt") } == cli.parse(["--file", "f.txt"])?
}

expect {
    cli = Cli.succeed(|verbosity| |file| { verbosity, file })
        |> Cli.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cli.with_opt(Opt.Spec.value("file").default("d.txt"))
    { verbosity: 0, file: "d.txt" } == cli.parse([])?
}

expect {
    cli = Cli.succeed(|verbosity| |file| { verbosity, file })
        |> Cli.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cli.with_opt(Opt.Spec.value("file"))
    { verbosity: 0, file: None } == cli.parse([])?
}

expect {
    cli = Cli.succeed(|verbosity| |file| { verbosity, file })
        |> Cli.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cli.with_param(Param.Spec.value("file"))
    { verbosity: 1, file: "f.txt" } == cli.parse(["-v", "f.txt"])?
}

expect {
    cli = Cli.succeed(|verbosity| |file| { verbosity, file })
        |> Cli.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cli.with_param(Param.Spec.value("file"))
    Err(MissingArguments(["file"])) == cli.parse(["-v"])
}

expect {
    cli = Cli.succeed(|verbosity| |files| { verbosity, files })
        |> Cli.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cli.with_param(Param.Spec.values("files"))
    Err(MissingArguments(["files"])) == cli.parse(["-v"])
}

expect {
    cli = Cli.succeed(|verbosity| |files| { verbosity, files })
        |> Cli.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cli.with_param(Param.Spec.values("files").optionals())
    { verbosity: 1, files: [] } == cli.parse(["-v"])?
}

expect {
    cli = Cli.succeed(|verbosity| |files| { verbosity, files })
        |> Cli.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cli.with_param(Param.Spec.values("files").optionals())
    { verbosity: 1, files: ["a.txt", "b.txt"] } == cli.parse(["-v", "a.txt", "b.txt"])?
}

expect {
    cli = Cli.succeed(|verbosity| |file| { verbosity, file })
        |> Cli.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cli.with_param(Param.Spec.value("file").optional())
    { verbosity: 1, file: None } == cli.parse(["-v"])?
}

expect {
    cli = Cli.succeed(|verbosity| |file| { verbosity, file })
        |> Cli.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cli.with_param(Param.Spec.value("file").optional().default("def.txt"))
    { verbosity: 1, file: "def.txt" } == cli.parse(["-v"])?
}

expect {
    cli = Cli.succeed(|verbosity| |file| { verbosity, file })
        |> Cli.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cli.with_param(Param.Spec.value("file").optional())
    { verbosity: 1, file: Some("f.txt") } == cli.parse(["-v", "f.txt"])?
}

expect {
    cli = Cli.succeed(|verbosity| |file| { verbosity, file })
        |> Cli.with_opt(Opt.Spec.one_of("verbosity",[("l", Low), ("m", Medium), ("h", High)]))
        |> Cli.with_param(Param.Spec.value("file").optional().default("def.txt"))
    { verbosity: Some(Low), file: "f.txt" } == cli.parse(["--verbosity", "l", "f.txt"])?
}

expect {
    cli = Cli.succeed(|verbosity| |file| { verbosity, file })
        |> Cli.with_opt(Opt.Spec.one_of("verbosity",[("l", Low), ("m", Medium), ("h", High)]))
        |> Cli.with_param(Param.Spec.value("file").optional().default("def.txt"))
    Err(InvalidOptValue("verbosity", ["low"])) == cli.parse(["--verbosity", "low", "f.txt"])
}

expect {
    cli = Cli.succeed(|verbosity| |file|{ verbosity, file })
        |> Cli.with_opt(Opt.Spec.count("verbosity").short("v"))
        |> Cli.with_param(Param.Spec.value("file"))
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
    "one" == tokenise(["one"], [], [expr_spec.info])?
        .params.get(expr_spec.info.name).ok_or([])
        |> (expr_spec.convert)()?
}
expect {
    expr_spec = Param.Spec.values("expr")
    ["one", "two", "3"] == tokenise(["one", "two", "3"], [], [expr_spec.info])?
        .params.get(expr_spec.info.name).ok_or([])
        |> (expr_spec.convert)()?
}
expect {
    expr_spec = Opt.Spec.values("expr").short("x")
    ["one", "two", "3"] == tokenise(["--expr", "one", "--expr=two", "--expr", "3"], [expr_spec.info], [])?
        .opts.get(expr_spec.info.long).ok_or([])
        |> (expr_spec.convert)()?
}
expect {
    expr_spec = Opt.Spec.count("expr").short("x")
    0 == tokenise([], [expr_spec.info], [])?
        .opts.get(expr_spec.info.long).ok_or([])
        |> (expr_spec.convert)()?
}
expect {
    expr_spec = Opt.Spec.count("expr").short("x")
    5 == tokenise(["-xxxxx"], [expr_spec.info], [])?
        .opts.get(expr_spec.info.long).ok_or([])
        |> (expr_spec.convert)()?
}
expect {
    expr_spec = Opt.Spec.value("expr").short("x")
    None == tokenise([], [expr_spec.info], [])?
        .opts.get(expr_spec.info.long).ok_or([])
        |> (expr_spec.convert)()?
}
expect {
    expr_spec = Opt.Spec.value("expr")
    Some("some expression") == tokenise(["--expr", "some expression"], [expr_spec.info], [])?
        .opts.get(expr_spec.info.long).ok_or([])
        |> (expr_spec.convert)()?
}
expect {
    expr_spec = Opt.Spec.value("expr").short("x")
    Err(MissingValue("expr")) == tokenise(["-x3"], [expr_spec.info], [])
}
expect {
    quiet_spec = Opt.Spec.flag("quiet").short("q")
    (quiet_spec.convert)(tokenise([], [quiet_spec.info], [])?.opts.get(quiet_spec.info.long).ok_or([]))?.not()
}
expect {
    quiet_spec = Opt.Spec.flag("quiet").short("q")
    (quiet_spec.convert)(tokenise(["-q"], [quiet_spec.info], [])?.opts.get(quiet_spec.info.long).ok_or([]))?
}

expect
    Cli.Opt.Info.{ kind: Count, short: "v", long: "verbosity", help: "verbosity level" }
        == Opt.Spec.count("verbosity").short("v").help("verbosity level").info

expect Dict.from_list([("verbosity", [""])])
    == tokenise(["--verbosity"], [Opt.Spec.count("verbosity").short("v").info], [])?.opts
expect Dict.from_list([("verbosity", [""])])
    == tokenise(["-v"], [Opt.Spec.count("verbosity").short("v").info], [])?.opts
expect Dict.from_list([("verbosity", ["", ""])])
    == tokenise(["-v", "-v"], [Opt.Spec.count("verbosity").short("v").info], [])?.opts
expect Dict.from_list([("verbosity", ["", "", ""])])
    == tokenise(["-vvv"], [Opt.Spec.count("verbosity").short("v").info], [])?.opts
expect Dict.from_list([("verbosity", [""]), ("exclusive", [""])])
    == tokenise(
        ["-v", "-x"],
        [
            Opt.Spec.count("verbosity").short("v").info,
            Opt.Spec.count("exclusive").short("x").info,
        ],
        [])?.opts
expect Dict.from_list([("verbosity", [""]), ("exclusive", [""])])
    == tokenise(
        ["--verbosity", "--exclusive"],
        [
            Opt.Spec.count("verbosity").info,
            Opt.Spec.flag("exclusive").info,
        ],
        [])?.opts
expect Dict.from_list([("verbosity", ["", ""]), ("exclusive", [""])])
    == tokenise(
        ["-vxv"],
        [
            Opt.Spec.count("verbosity").short("v").info,
            Opt.Spec.count("exclusive").short("x").info,
        ],
        [])?.opts
expect Dict.from_list([("verbosity", ["", ""]), ("exclusive", ["", ""])])
    == tokenise(
        ["-vxv", "-x"],
        [
            Opt.Spec.count("verbosity").short("v").info,
            Opt.Spec.count("exclusive").short("x").info,
        ],
        [])?.opts
expect {
    Err(UnexpectedValue("verbosity"))
        == tokenise(["--verbosity=3"], [Opt.Spec.count("verbosity").info], [])
}
expect Err(UnknownOption("x"))
    == tokenise(["-x"], [Opt.Spec.count("verbosity").short("v").info], [])
expect {
    Err(UnknownOption("excl"))
        == tokenise(["--excl"], [Opt.Spec.count("verbosity").short("v").info], [])
}
expect {
    Dict.from_list([("file", ["f.txt"])])
        == tokenise(
            ["--file=f.txt"],
            [
                Opt.Spec.value("file").short("f").info,
            ],
            [])?.opts
}
expect {
    Dict.from_list([("file", ["f.txt"])])
        == tokenise(
            ["--file", "f.txt"],
            [
                Opt.Spec.value("file").short("f").info,
            ],
            [])?.opts
}
expect {
    Dict.from_list([("file", ["f.txt", "g.txt"])])
        == tokenise(
            ["--file", "f.txt", "--file=g.txt"],
            [
                Opt.Spec.values("file").info,
            ],
            [])?.opts
}
expect {
    Dict.from_list([("offset", ["-5"])])
        == tokenise(
            ["--offset", "-5"],
            [
                Opt.Spec.value("offset").info,
            ],
            [])?.opts
}

expect Dict.from_list([("file", ["f.txt"])])
    == tokenise(
        ["f.txt"],
        [],
        [
            Param.Spec.value("file").info,
        ])?.params
expect {
        params: Dict.from_list([("files", ["f.txt", "g.txt"]), ("expr", ["error"])]),
        opts: Dict.from_list([("invert", [""])])
    } == tokenise(
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
    } == tokenise(
        ["-v", "error", "f.txt", "g.txt"],
        [
            Opt.Spec.flag("invert").short("v").info,
        ],
        [
            Param.Spec.value("expr").info,
            Param.Spec.values("files").optional().info,
        ])?
expect {
    Err(MissingArguments(["files"])) == tokenise(
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
    } == tokenise(
        ["-v", "error"],
        [
            Opt.Spec.flag("invert").short("v").info,
        ],
        [
            Param.Spec.value("expr").info,
            Param.Spec.values("files").optional().info,
        ])?
expect {
    Err(MandatoryParamAfterOptional("files")) == tokenise(
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
    Err(VariadicParamNotLast("files")) == tokenise(
        ["-v", "error", "f.txt", "g.txt"],
        [
            Opt.Spec.flag("invert").short("v").info,
        ],
        [
            Param.Spec.values("files").info,
            Param.Spec.value("expr").info,
        ])
}

expect {
    cli = Cli.succeed(|file|
                        { file })
        |> Cli.with_param(Cli.Param.Spec.value("file"))
    Err(ShowHelp("\n    --help  display this help text and exit")) == cli.parse(["--help"])
}

expect {
    cli = Cli.succeed(|regexp_type| |patterns_file| |max_count| |files|
                        { regexp_type, patterns_file, max_count, files })
        |> Cli.with_usage(\\app [OPTION]... [FILE]...
                            \\description
                            \\example
                            )
        |> Cli.with_coda(\\Explainations and contact details here
                            )
        |> Cli.with_opt_help_section("A logical group of options:")
        |> Cli.with_opt(Cli.Opt.Spec.flag("extended-regexp")
            .short("E")
            .help("PATTERNS are extended regular expressions"))
        |> Cli.with_opt(Cli.Opt.Spec.value("file")
            .short("f")
            .help("take PATTERNS from FILE")
            .symbol("FILE"))
        |> Cli.with_opt(Cli.Opt.Spec.value("max-count")
            .integer()
            .help("stop after NUM lines selected")
            .symbol("NUM"))
        |> Cli.with_param(Cli.Param.Spec.value("file"))
    cli.to_help_str() == \\app [OPTION]... [FILE]...
                         \\description
                         \\example
                         \\
                         \\
                         \\A logical group of options:
                         \\-E, --extended-regexp  PATTERNS are extended regular expressions
                         \\-f, --file=FILE        take PATTERNS from FILE
                         \\    --max-count=NUM    stop after NUM lines selected
                         \\
                         \\    --help             display this help text and exit
                         \\
                         \\Explainations and contact details here
}

expect {
    cli = Cli.succeed(|invert| |file| { invert, file })
        |> Cli.with_opt(Cli.Opt.Spec.flag("invert").short("v"))
        |> Cli.with_param(Cli.Param.Spec.value("file"))
    { invert: False, file: "-" } == cli.parse(["-"])?
}
expect {
    cli = Cli.succeed(|invert| |files| { invert, files })
        |> Cli.with_opt(Cli.Opt.Spec.flag("invert").short("v"))
        |> Cli.with_param(Cli.Param.Spec.values("files"))
    { invert: False, files: ["-v", "f.txt"] } == cli.parse(["--", "-v", "f.txt"])?
}

expect {
    commit_cli = Cli.succeed(|message| |amend| { message, amend })
        .with_opt(Cli.Opt.Spec.value("message"))
        .with_opt(Cli.Opt.Spec.flag("amend"))

    add_cli = Cli.succeed(|name| |url| { name, url })
        .with_param(Cli.Param.Spec.value("name"))
        .with_param(Cli.Param.Spec.value("url").optional())

    cli = Cli.succeed(|git_dir| |no_pager| |cmd| |file|{ git_dir, no_pager, cmd, file })
        .with_opt(Cli.Opt.Spec.value("git-dir"))
        .with_opt(Cli.Opt.Spec.flag("no-pager"))
        .with_subcommands([
            Cli.Subcommand.command("commit", commit_cli.map(|c| Commit(c))),
            Cli.Subcommand.command("add", add_cli.map(|c| Add(c))),
        ])
        .with_param(Cli.Param.Spec.value("file"))
    Err(SubcommandNotLast) == cli.parse([])
}

expect {
    commit_cli = Cli.succeed(|message| |amend| { message, amend })
        .with_opt(Cli.Opt.Spec.value("message"))
        .with_opt(Cli.Opt.Spec.flag("amend"))

    add_cli = Cli.succeed(|name| |url| { name, url })
        .with_param(Cli.Param.Spec.value("name"))
        .with_param(Cli.Param.Spec.value("url").optional())

    cli = Cli.succeed(|git_dir| |no_pager| |cmd| { git_dir, no_pager, cmd })
        .with_opt(Cli.Opt.Spec.value("git-dir"))
        .with_opt(Cli.Opt.Spec.flag("no-pager"))
        .with_subcommands([
            Cli.Subcommand.command("commit", commit_cli.map(|c| Commit(c))),
            Cli.Subcommand.command("add", add_cli.map(|c| Add(c))),
        ])
    Err(UnknownOption("bogus")) == cli.parse(["commit", "--bogus", "--help"])
}
