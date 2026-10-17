# SPDX-License-Identifier: UPL-1.0
# Copyright (c) 2026 Simon Redding

import tabulate.Table

## A declarative command-line interface that parses a list of arguments into a
## value of type `a`.
##
## Build one applicative-style. Start with [Cli.succeed], giving it a curried
## function, then pipe it through [Cli.with_opt], [Cli.with_param] and friends.
## Each step supplies the function's next argument, in the order you add them, so
## the parsed result is whatever the function finally returns.
##
## ```roc
## cli = Cli.succeed(|verbosity| |file| { verbosity, file })
##     |> Cli.with_opt(Cli.Opt.Spec.count("verbosity").short("v"))
##     |> Cli.with_param(Cli.Param.Spec.value("file"))
##
## expect cli.parse(["-v", "f.txt"]) == Ok({ verbosity: 1, file: "f.txt" })
## ```
##
## Arguments are understood as follows:
##
## - `--name value` and `--name=value` give a long option its value.
## - `-abc` is a cluster of short options. Each must take no value (flags and
##   counts), so `-vvv` counts three times.
## - `--` ends option processing, so everything after it is a positional
##   parameter. A lone `-` is also a positional parameter.
## - `--help` stops parsing and returns the generated help text as
##   `Err(ShowHelp(text))`.
##
## Problems with how the interface itself is declared (clashing option names,
## misordered parameters, subcommands mixed with parameters) are reported by
## [Cli.parse], not when the interface is built.
Cli(a) :: {
    opt_infos: List(Cli.Opt.Info),
    param_infos: List(Cli.Param.Info),
    assemble: Raw -> Try(a, CliError),
    usage: Str,
    sections : Dict(U64, Str),
    coda: Str,
    commands: List({ name: Str, help: Str }),
}.{
    ## Parses `argv` against the interface.
    ##
    ## `argv` is the list of arguments *without* the program name. On success the
    ## result is the value built by the function given to [Cli.succeed]. On failure
    ## the result is a [Cli.CliError] saying what was wrong.
    ##
    ## If `--help` is given (and you haven't declared an option of that name), the
    ## result is `Err(ShowHelp(text))`, where `text` is the output of
    ## [Cli.to_help_str].
    ##
    ## ```roc
    ## expect {
    ##     cli = Cli.succeed(|verbosity| |file| { verbosity, file })
    ##         |> Cli.with_opt(Cli.Opt.Spec.count("verbosity").short("v"))
    ##         |> Cli.with_opt(Cli.Opt.Spec.value("file"))
    ##     cli.parse(["-v", "--file", "f.txt"]) == Ok({ verbosity: 1, file: Some("f.txt") })
    ## }
    ## ```
    parse : Cli(a), List(Str) -> Try(a, CliError)
    parse = |cli, argv|
        match tokenise(argv, cli.opt_infos, cli.param_infos) {
            Ok(ts) => (cli.assemble)(ts)
            Err(RenderHelp) => Err(ShowHelp(cli.to_help_str()))
            Err(e) => Err(e)
        }

    ## Renders the help text for the interface.
    ##
    ## The text has up to three parts, separated by blank lines: the usage text set
    ## by [Cli.with_usage], then a table, then the coda set by [Cli.with_coda].
    ## Empty parts are left out. The table lists the options, then the
    ## subcommands, then the built-in `--help` line, and any headings added with
    ## [Cli.with_opt_help_section] appear inside it.
    ##
    ## ```roc
    ## expect {
    ##     cli = Cli.succeed(|file| { file })
    ##         |> Cli.with_param(Cli.Param.Spec.value("file"))
    ##     cli.to_help_str() == "    --help  display this help text and exit"
    ## }
    ## ```
    to_help_str : Cli(a) -> Str
    to_help_str = |self| {
        options_commands_help = Table.plain.format(
            self.opt_infos.map(|i| i.to_help_str())
                .concat(self.commands.map(|c| ["  ${c.name}", " ${c.help}"]))
                .append(["${help_option}", " display this help text and exit"]))
            .fold_with_index([], |lines, row, i|
                lines.append([
                        match self.sections.get(i) {
                            Ok(heading) => "${if i > 0 "\n" else ""}${heading}\n"
                            _  if i > 0
                                and (i == self.opt_infos.len()
                                    or i == self.opt_infos.len() + self.commands.len()) => "\n"
                            _ => ""
                        },
                        "${row}"
                    ] |> Str.join_with("")))
            |> Str.join_with("\n")

        [self.usage, options_commands_help, self.coda]
            .drop_if(|s| s.is_empty())
            |> Str.join_with("\n\n")
    }

    ## Creates an interface with no options or parameters that always parses to
    ## `value`.
    ##
    ## This is where every interface starts. Give it a curried function, with one
    ## argument for each option and parameter you are going to add, in that order.
    ##
    ## ```roc
    ## Cli.succeed(|verbosity| |file| { verbosity, file })
    ## ```
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

    ## Sets the usage text shown at the top of the help output, such as the command
    ## synopsis and a short description.
    with_usage : Cli(a), Str -> Cli(a)
    with_usage = |cli, usage| { ..cli, usage }

    ## Sets the text shown at the end of the help output, after the options. Use it
    ## for explanations, examples or contact details.
    with_coda : Cli(a), Str -> Cli(a)
    with_coda = |cli, coda| { ..cli, coda }

    ## Starts a new headed section in the help output, with `text` as its heading.
    ##
    ## The heading is placed before whatever is listed next: the next option added
    ## after this call, or the subcommands and `--help` line if no more options
    ## follow. Call it *before* adding the options that belong under the heading.
    ##
    ## ```roc
    ## Cli.succeed(|extended| { extended })
    ##     |> Cli.with_opt_help_section("A logical group of options:")
    ##     |> Cli.with_opt(Cli.Opt.Spec.flag("extended-regexp").short("E"))
    ## ```
    with_opt_help_section : Cli(a), Str -> Cli(a)
    with_opt_help_section  = |cli, text|
        { ..cli, sections: cli.sections.insert(cli.opt_infos.len(), text) }

    ## Adds a group of mutually exclusive flags that together supply a single value.
    ##
    ## Each entry pairs a flag spec with the value it stands for. The next argument
    ## of the function given to [Cli.succeed] receives:
    ##
    ## - the value of the flag that was given, if exactly one was;
    ## - `default` if none were given;
    ## - nothing at all if several were, as that is `Err(ConflictingOpts(names))`
    ##   listing the long names of the flags that clashed.
    ##
    ## ```roc
    ## Cli.succeed(|verbosity| { verbosity })
    ##     |> Cli.with_opt_group([
    ##         (Cli.Opt.Spec.flag("high"), High),
    ##         (Cli.Opt.Spec.flag("med"), Medium),
    ##         (Cli.Opt.Spec.flag("low"), Low),
    ##     ], Low)
    ## ```
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

    ## Adds an option. The option's converted value becomes the next argument of
    ## the function given to [Cli.succeed].
    ##
    ## If the option's value can't be converted, for example a non-number given to an
    ## option marked with [Cli.Opt.Spec.integer], the result is
    ## `Err(InvalidOptValue(long_name, values))`.
    ##
    ## ```roc
    ## Cli.succeed(|verbosity| |file| { verbosity, file })
    ##     |> Cli.with_opt(Cli.Opt.Spec.count("verbosity").short("v"))
    ##     |> Cli.with_opt(Cli.Opt.Spec.value("file"))
    ## ```
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

    ## Adds a positional parameter. The parameter's converted value becomes the next
    ## argument of the function given to [Cli.succeed].
    ##
    ## Parameters are matched to positional arguments in the order they are added.
    ## Mandatory parameters must come before optional ones, and a parameter that
    ## takes several values (see [Cli.Param.Spec.values]) must come last.
    ##
    ## If the value can't be converted the result is
    ## `Err(InvalidParamValue(name, values))`.
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

    ## A named subcommand, such as `commit` in `git commit`, with its own [Cli] that
    ## parses the arguments following its name.
    ##
    ## Create one with [Cli.Subcommand.command] and describe it in the help output
    ## with [Cli.Subcommand.help].
    Subcommand(a) :: {
        name: Str,
        help: Str ?? "",
        cli: Cli(a),
    }.{
        ## Creates a subcommand called `name`, whose arguments are parsed by `cli`.
        command : Str, Cli(a) -> Subcommand(a)
        command = |name, cli| Subcommand.{ name, cli }

        ## Sets the one-line description shown next to the subcommand in the help output.
        help : Subcommand(a),  Str -> Subcommand(a)
        help = |cmd, text| { ..cmd, help: text }
    }

    ## Adds subcommands. The parsed result of the subcommand that was chosen becomes
    ## the next argument of the function given to [Cli.succeed].
    ##
    ## The first positional argument selects the subcommand and every argument after
    ## it is parsed by that subcommand's own [Cli]. Options given *before* the
    ## subcommand name are parsed by this interface. All subcommands must produce the
    ## same type, so use [Cli.map] to wrap each result in its own tag.
    ##
    ## A subcommand selector can't be combined with other positional parameters;
    ## doing so gives `Err(ParamSubcommandConflict)` from [Cli.parse]. An unrecognised
    ## name gives `Err(UnknownSubcommand(name))` and no name at all gives
    ## `Err(MissingSubcommand)`.
    ##
    ## ```roc
    ## cli = Cli.succeed(|git_dir| |cmd| { git_dir, cmd })
    ##     |> Cli.with_opt(Cli.Opt.Spec.value("git-dir"))
    ##     |> Cli.with_subcommands([
    ##         Cli.Subcommand.command("commit", commit_cli.map(|c| Commit(c))),
    ##         Cli.Subcommand.command("add", add_cli.map(|c| Add(c))),
    ##     ])
    ## ```
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

    ## Transforms the parsed result with `fn`, leaving the options and parameters
    ## unchanged.
    ##
    ## This is mostly useful for tagging the result of a subcommand's interface
    ## before passing it to [Cli.with_subcommands].
    ##
    ## ```roc
    ## add_cli.map(|args| Add(args))
    ## ```
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

    ## A value that may be absent. Options and parameters that you haven't marked
    ## with a default produce an `Optional` where `None` means it wasn't supplied.
    Optional(a) : [Some(a), None]

    ## Everything that can go wrong while declaring or parsing a [Cli].
    ##
    ## - `UnknownOption(name)`: an option that hasn't been declared was given.
    ## - `MissingValue(name)`: an option that takes a value was given without one.
    ## - `UnexpectedValue(name)`: a value was supplied to an option that takes none,
    ##   such as `--verbose=3`.
    ## - `RepeatedOption(name)`: a single-valued option was given twice, or two
    ##   declared options share a long or short name.
    ## - `TrailingParameters(args)`: there were more positional arguments than
    ##   parameters declared.
    ## - `VariadicParamNotLast(name)`: a parameter that takes several values wasn't
    ##   the last parameter.
    ## - `MissingArguments(names)`: mandatory parameters weren't supplied.
    ## - `MandatoryParamAfterOptional(name)`: a mandatory parameter was declared
    ##   after an optional one.
    ## - `ShowHelp(text)`: help was requested with `--help`. `text` is the help
    ##   message, ready to print.
    ## - `RenderHelp`: internal signal that `--help` was seen. [Cli.parse] turns it
    ##   into `ShowHelp`, so you shouldn't see it.
    ## - `InvalidOptValue(name, values)`: an option's value couldn't be converted.
    ## - `InvalidParamValue(name, values)`: a parameter's value couldn't be
    ##   converted.
    ## - `ConflictingOpts(names)`: more than one flag in an option group was given.
    ## - `UnknownSubcommand(name)`: the subcommand isn't one of those declared.
    ## - `MissingSubcommand`: subcommands were declared but none was given.
    ## - `ParamSubcommandConflict`: subcommands were mixed with other parameters.
    ## - `DuplicateSubcommand(name)`: reserved for a repeated subcommand name. This
    ##   module doesn't currently produce it.
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
        ParamSubcommandConflict,
        DuplicateSubcommand(Str),
    ]

    ## Options: the `--long` and `-s` arguments of a command line.
    ##
    ## Create a [Cli.Opt.Spec] with one of [Cli.Opt.Spec.flag], [Cli.Opt.Spec.count],
    ## [Cli.Opt.Spec.value], [Cli.Opt.Spec.values] or [Cli.Opt.Spec.one_of], refine it
    ## with the other functions on `Spec`, then add it to a [Cli] with
    ## [Cli.with_opt].
    Opt :: {}.{
        ## What sort of option this is.
        ##
        ## - `Flag`: takes no value, and is either present or absent.
        ## - `Count`: takes no value, and can be repeated to count occurrences.
        ## - `Value`: takes one value, and may be given at most once.
        ## - `Values`: takes a value each time, and may be repeated.
        Kind : [Flag, Count, Value, Values]
        ## The declared details of an option, without how its value is converted:
        ## its [Cli.Opt.Kind], its long name, an optional one-character short name, its
        ## help text and the placeholder symbol shown for its value in the help output.
        Info :: { kind: Kind, long: Str, short: Str ?? "", help: Str ?? "", symbol: Str ?? ""}.{
            ## Two infos are equal when every field is equal.
            is_eq : Info, Info -> Bool
            is_eq = |self, other|
                self.kind == other.kind
                    and self.short == other.short
                    and self.long == other.long
                    and self.help == other.help
                    and self.symbol == other.symbol

            ## Returns the two cells of this option's row in the help table: the
            ## `-s, --long=SYMBOL` column and the help text column.
            ##
            ## Options without a short name are padded so that long names line up.
            to_help_str : Info -> List(Str)
            to_help_str = |self| {
                short = match self.short {
                    "" => "    "
                    s => "-${s}, "
                }
                long = match self.kind {
                    Value | Values if self.symbol.is_empty().not() => "--${self.long}=${self.symbol}"
                    _ => "--${self.long}"
                }
                ["${short}${long}", " ${self.help}"]
            }
        }
        ## An option specification: its [Cli.Opt.Info] together with the function that
        ## converts the strings collected for it into a value of type `a`.
        ##
        ## Start from [Cli.Opt.Spec.flag], [Cli.Opt.Spec.count], [Cli.Opt.Spec.value],
        ## [Cli.Opt.Spec.values] or [Cli.Opt.Spec.one_of], then chain the others, and
        ## pass the result to [Cli.with_opt].
        Spec(a) :: { info: Info, convert: List(Str) -> Try(a, [TypeMismatch, NotFound]) }.{
            ## An option that counts how many times it was given. The value is `0` if it
            ## never was, so `-vvv` and `-v -v -v` both give `3`.
            ##
            ## ```roc
            ## Cli.Opt.Spec.count("verbosity").short("v")
            ## ```
            count : Str -> Spec(U64)
            count = |long| Spec.{ info: Info.{ kind: Count, long }, convert: convert_count }

            ## An option that takes no value. The value is `Bool.True` if it was given and
            ## `Bool.False` otherwise.
            ##
            ## ```roc
            ## Cli.Opt.Spec.flag("invert").short("v")
            ## ```
            flag : Str -> Spec(Bool)
            flag = |long| Spec.{ info: Info.{ kind: Flag, long }, convert: convert_flag }

            ## An option that takes a single value, as `--file f.txt` or `--file=f.txt`.
            ## The value is `None` if the option wasn't given, and giving it twice is
            ## `Err(RepeatedOption(name))`.
            ##
            ## Chain [Cli.Opt.Spec.default] to replace the `None`, or [Cli.Opt.Spec.integer]
            ## to parse a number.
            value : Str -> Spec(Optional(Str))
            value = |long| Spec.{ info: Info.{ kind: Value, long }, convert: convert_optional_value }

            ## An option that takes a value which must be one of the given strings, each
            ## mapped to a value of your own type. The result is `None` if the option wasn't
            ## given, and a string that isn't listed is `Err(InvalidOptValue(name, values))`.
            ##
            ## ```roc
            ## Cli.Opt.Spec.one_of("verbosity", [("l", Low), ("m", Medium), ("h", High)])
            ## ```
            one_of : Str, List((Str, a)) -> Spec(Optional(a))
            one_of = |long, options|
                Spec.{
                    info: Info.{ kind: Value, long },
                    convert: convert_one_of(Dict.from_list(options))
                }

            ## An option that takes a value each time it is given and may be repeated. The
            ## values are collected in order, and the list is empty if it was never given.
            ##
            ## ```roc
            ## Cli.Opt.Spec.values("file")  # --file f.txt --file=g.txt gives ["f.txt", "g.txt"]
            ## ```
            values : Str -> Spec(List(Str))
            values = |long| Spec.{ info: Info.{ kind: Values, long }, convert: convert_values}

            ## Gives the option a one-character short name, so `-v` can stand in for
            ## `--verbose`. Short options can be combined, as in `-vxv`.
            ##
            ## Short names are currently only understood for options that take no value
            ## (flags and counts). Options that take values must be given in long form.
            short : Spec(a), Str -> Spec(a)
            short = |spec, s| { ..spec, info: { ..spec.info, short: s } }

            ## Converts a [Cli.Opt.Spec.value] option to a 64-bit integer. A value that
            ## isn't a number is `Err(InvalidOptValue(name, values))`.
            ##
            ## ```roc
            ## Cli.Opt.Spec.value("verbosity").integer().default(56)
            ## ```
            integer : Spec(Optional(Str)) -> Spec(Optional(I64))
            integer = |spec| {
                info: spec.info,
                convert: to_optional_integer(spec.convert)
            }

            ## Replaces `None` with `def` when the option wasn't given, so the result is no
            ## longer wrapped in an [Cli.Optional].
            ##
            ## ```roc
            ## Cli.Opt.Spec.value("file").default("d.txt")
            ## ```
            default : Spec(Optional(a)), a -> Spec(a)
            default = |spec, def| {
                info: spec.info,
                convert: with_default(spec.convert, def)
            }

            ## Sets the option's description in the help output.
            help : Spec(a), Str -> Spec(a)
            help = |spec, help| { ..spec, info: { ..spec.info, help } }

            ## Sets the placeholder shown for the option's value in the help output, as in
            ## `--file=FILE`. It is only shown for options that take values.
            symbol : Spec(a), Str -> Spec(a)
            symbol = |spec, symbol| { ..spec, info: { ..spec.info, symbol } }
        }
    }

    ## Positional parameters: the arguments that aren't options.
    ##
    ## Create a [Cli.Param.Spec] with [Cli.Param.Spec.value] or
    ## [Cli.Param.Spec.values], refine it with the other functions on `Spec`, then add
    ## it to a [Cli] with [Cli.with_param].
    Param :: {}.{
        ## What sort of parameter this is.
        ##
        ## - `Value`: takes exactly one argument.
        ## - `Values`: takes all of the remaining arguments.
        ## - `Command`: selects a subcommand. [Cli.with_subcommands] adds this for you.
        Kind : [Value, Values, Command]
        ## The declared details of a parameter without how its value is converted: its
        ## [Cli.Param.Kind], its name and whether it is mandatory (the default).
        Info :: { kind: Kind, name: Str, mandatory: Bool ?? Bool.True }.{
            ## Two infos are equal when every field is equal.
            is_eq : Info, Info -> Bool
            is_eq = |self, other|
                self.kind == other.kind
                    and self.name == other.name
                    and self.mandatory == other.mandatory
        }
        ## A parameter specification: its [Cli.Param.Info] together with the function
        ## that converts the strings collected for it into a value of type `a`.
        ##
        ## Start from [Cli.Param.Spec.value] or [Cli.Param.Spec.values], chain the
        ## others, and pass the result to [Cli.with_param].
        Spec(a) :: { info: Info, convert: List(Str) -> Try(a, [TypeMismatch, NotFound])}.{
            ## A mandatory parameter that takes one argument. Leaving it out is
            ## `Err(MissingArguments(names))`.
            ##
            ## ```roc
            ## Cli.Param.Spec.value("file")
            ## ```
            value : Str -> Spec(Str)
            value = |name| Spec.{ info: Info.{ name, kind: Value }, convert: convert_value }

            ## A parameter that takes all of the remaining arguments. At least one is
            ## required unless you chain [Cli.Param.Spec.optionals]. It must be the last
            ## parameter.
            ##
            ## ```roc
            ## Cli.Param.Spec.values("files").optionals()
            ## ```
            values : Str -> Spec(List(Str))
            values = |name| Spec.{ info: Info.{ name, kind: Values }, convert: convert_values}

            ## Converts a [Cli.Param.Spec.value] parameter to a 64-bit integer. An argument
            ## that isn't a number is `Err(InvalidParamValue(name, values))`.
            ##
            ## ```roc
            ## Cli.Param.Spec.value("length").integer()
            ## ```
            integer : Spec(Str) -> Spec(I64)
            integer = |spec| {
                info: spec.info,
                convert: to_integer(spec.convert)
            }

            ## Makes a [Cli.Param.Spec.values] parameter optional, so that zero arguments are
            ## allowed and the value is an empty list.
            optionals : Spec(List(a)) -> Spec(List(a))
            optionals = |spec| { ..spec, info: { ..spec.info, mandatory: Bool.False } }

            ## Makes a parameter optional. The value is `None` if the argument wasn't given.
            ## Optional parameters must come after all mandatory ones.
            ##
            ## ```roc
            ## Cli.Param.Spec.value("file").optional()
            ## ```
            optional : Spec(a) -> Spec(Optional(a))
            optional = |spec| {
                info: { ..spec.info, mandatory: Bool.False },
                convert: make_optional(spec.convert),
            }

            ## Replaces `None` with `def` when an optional parameter wasn't given, so the
            ## result is no longer wrapped in an [Cli.Optional]. Use it after
            ## [Cli.Param.Spec.optional].
            ##
            ## ```roc
            ## Cli.Param.Spec.value("file").optional().default("def.txt")
            ## ```
            default : Spec(Optional(a)), a -> Spec(a)
            default = |spec, def| {
                info: spec.info,
                convert: with_default(spec.convert, def)
            }
        }
    }
}

# The arguments after tokenising, before conversion: the strings collected for each option and each parameter, by name.
Raw : { opts: Dict(Str, List(Str)), params: Dict(Str, List(Str)) }

# Records one occurrence of an option, checking that its value (or lack of one) suits its kind.
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

# Records one positional argument against its parameter.
add_param : Raw, Cli.Param.Info, Str -> Raw
add_param = |raw, info, value|
    match info.kind {
        Value => { ..raw, params: raw.params.insert(info.name, [value]) }
        Values | Command => { ..raw, params: upsert(raw.params, info.name, value) }
    }

# Looks an option up by long or short name. An unknown `help` is not an error but asks for the help text to be rendered.
get_opt_info : Dict(Str, Cli.Opt.Info), Str -> Try(Cli.Opt.Info, _)
get_opt_info = |infos, name|
    match infos.get(name) {
        Ok(info) => Ok(info)
        _ if name == "help" => Err(RenderHelp)
        _ => Err(UnknownOption(name))
    }

# A subcommand selector must be the only parameter.
validate_subcommands: List(Cli.Param.Info) -> Try({}, _)
validate_subcommands = |infos| {
    match infos.map(|i| i.kind) {
        [Command]=> Ok({})
        ks if ks.contains(Command).not() => Ok({})
        _ => Err(ParamSubcommandConflict)
    }
}

# Splits `argv` into option and parameter values, validating the declarations as it goes.
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

# The built-in `--help` row of the help table.
help_option = "    --help"

# Converter wrappers: each adapts a converter to produce a different type, or fills in an absent value.
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

# Appends `v` to the list stored under `k`, creating the list if it doesn't exist.
upsert : Dict(a, List(b)), a, b -> Dict(a, List(b))
    where [a.is_eq : a, a -> Bool, a.to_hash : a, Hasher -> Hasher]
upsert = |d, k, v|
    d.update(k, |ov|
        match ov {
            Ok(vs) => Ok(vs.append(v))
            Err(Missing) => Ok([v])
        })

# Converters: turn the strings collected for an option or parameter into a typed value.
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
    Err(ShowHelp("    --help  display this help text and exit")) == cli.parse(["--help"])
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
    Err(ParamSubcommandConflict) == cli.parse([])
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
