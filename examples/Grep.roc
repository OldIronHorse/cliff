import cliff.Cli

Grep := {}.{
    cli = Cli.succeed(|regexp_type| |pattern_regexp| |pattern_file| |case| |invert_match| |max_count| |include| |pattern_and_files|
                             { regexp_type, pattern_regexp, pattern_file, case, invert_match, max_count, include, pattern_and_files })
        .with_usage(\\grep [OPTION]... PATTERNS [FILE]...
                            \\Search for PATTERNS in each FILE.
                            \\Example: grep -i 'hello world' menu.h main.c
                            )
        .with_coda(\\When FILE is '-', read standard input.  With no FILE, read '.' if
                           \\recursive, '-' otherwise.  With fewer than two FILEs, assume -h.
                           \\Exit status is 0 if any line is selected, 1 otherwise;
                           \\if any error occurs and -q is not given, the exit status is 2.
                           \\
                           \\Report bugs to: bug-grep@gnu.org
                           \\GNU grep home page: <https://www.gnu.org/software/grep/>
                           \\General help using GNU software: <https://www.gnu.org/gethelp/>
                           )
        .with_opt_help_section("Pattern selection and interpretation:")
        .with_opt_group(
            [
                (Cli.Opt.Spec.flag("extended-regexp")
                    .short("E")
                    .help("PATTERNS are extended regular expressions"), Extended),
                (Cli.Opt.Spec.flag("fixed-strings")
                    .short("F")
                    .help("PATTERNS are strings"), Fixed),
                (Cli.Opt.Spec.flag("basic-regexp")
                    .short("G")
                    .help("PATTERNS are basic regular expressions (default)"), Basic),
                (Cli.Opt.Spec.flag("perl-regexp")
                    .short("P")
                    .help("PATTERNS are Perl regular expressions"), Perl),
            ], Basic)
        .with_opt(Cli.Opt.Spec.value("regexp")
            .short("e")
            .help("use REGEXP for matching")
            .symbol("REGEXP"))
        .with_opt(Cli.Opt.Spec.value("file")
            .short("f")
            .help("take PATTERNS from FILE")
            .symbol("FILE"))
        .with_opt_group(
            [
                (Cli.Opt.Spec.flag("ignore-case")
                    .short("i")
                    .help("ignore case distinctions in patterns and data"), Ignore),
                (Cli.Opt.Spec.flag("no-ignore-case")
                    .help("do not ignore case distinctions (default)"), Respect),
            ], Respect)
        .with_opt(Cli.Opt.Spec.flag("invert-match")
            .short("v")
            .help("select non-matching lines"))
        .with_opt_help_section("Output control:")
        .with_opt(Cli.Opt.Spec.value("max-count")
            .short("m")
            .integer()
            .help("stop after NUM lines selected")
            .symbol("NUM"))
        .with_opt(Cli.Opt.Spec.values("include")
            .help("search only files that match GLOB (a file pattern)")
            .symbol("GLOB"))
        .with_param(Cli.Param.Spec.values("args").optionals())
}

base_expected = {
    regexp_type: Basic,
    case: Respect,
    invert_match: False,
    max_count: None,
    include: [],
    pattern_and_files: ["some words"],
    pattern_regexp: None,
    pattern_file: None
}

expect { ..base_expected, pattern_and_files: [] } == Grep.cli.parse([])?
expect base_expected == Grep.cli.parse(["some words"])?
expect { ..base_expected, pattern_and_files: ["some words", "f.txt"] } == Grep.cli.parse(["some words", "f.txt"])?
expect { ..base_expected, regexp_type: Extended, pattern_and_files: ["some words", "f.txt"] }
    == Grep.cli.parse(["-E", "some words", "f.txt"])?
expect { ..base_expected, regexp_type: Extended } == Grep.cli.parse(["-E", "some words"])?
expect { ..base_expected, regexp_type: Fixed } == Grep.cli.parse(["-F", "some words"])?
expect { ..base_expected, regexp_type: Basic } == Grep.cli.parse(["-G", "some words"])?
expect { ..base_expected, regexp_type: Perl } == Grep.cli.parse(["-P", "some words"])?
expect { ..base_expected, case: Ignore, regexp_type: Perl }
    == Grep.cli.parse(["-i", "-P", "some words"])?
expect { ..base_expected, case: Ignore} == Grep.cli.parse(["-i", "some words"])?
expect base_expected == Grep.cli.parse(["--no-ignore-case", "some words"])?
expect { ..base_expected, invert_match: True } == Grep.cli.parse(["-v", "some words"])?
expect { ..base_expected, max_count: Some(100) } == Grep.cli.parse(["--max-count", "100", "some words"])?
expect { ..base_expected, include: ["inc1", "inc2"] } == Grep.cli.parse(["--include=inc1", "--include=inc2", "some words"])?
