app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst" }

import pf.OsStr
import pf.Stdout
import Cliff

main! : List(OsStr) => Try({}, _)
main! = |argv| {
    match argv.map_try(OsStr.to_str_try) {
        Ok(args) =>
            match cli_grep.parse(args) {
                Ok(cfg) =>
                    Stdout.line!("running... ${Str.inspect(args)} ${Str.inspect(cfg)}")
                Err(ShowHelp) =>
                    Stdout.line!(cli_grep.to_help_str())
                Err(e) =>
                    e |> Str.inspect() |> Stdout.line!()
            }
        Err(e) =>
            e |> Str.inspect() |> Stdout.line!()
    }
}

cli_grep = Cliff.succeed(|regexp_type| |pattern_regexp| |pattern_file| |case| |invert_match| |max_count| |include| |pattern_and_files|
                         { regexp_type, pattern_regexp, pattern_file, case, invert_match, max_count, include, pattern_and_files })
    |> Cliff.with_usage(\\grep [OPTION]... PATTERNS [FILE]...
                        \\Search for PATTERNS in each FILE.
                        \\Example: grep -i 'hello world' menu.h main.c
                        )
    |> Cliff.with_opt_help_section("Pattern selection and interpretation:")
    |> Cliff.with_opt_group(
        [
            (Cliff.Opt.Spec.flag("extended-regexp").short("E").help({ text: "PATTERNS are extended regular expressions" }), Extended),
            (Cliff.Opt.Spec.flag("fixed-strings").short("F").help({ text: "PATTERNS are strings" }), Fixed),
            (Cliff.Opt.Spec.flag("basic-regexp").short("G").help({ text: "PATTERNS are basic regular expressions (default)" }), Basic),
            (Cliff.Opt.Spec.flag("perl-regexp").short("P").help({ text: "PATTERNS are Perl regular expressions" }), Perl),
        ], Basic)
    |> Cliff.with_opt(Cliff.Opt.Spec.value("regexp").short("e").help({ text: "use REGEXP for matching", symbol: "REGEXP" }))
    |> Cliff.with_opt(Cliff.Opt.Spec.value("file").short("f").help({ text: "take PATTERNS from FILE", symbol: "FILE" }))
    |> Cliff.with_opt_group(
        [
            (Cliff.Opt.Spec.flag("ignore-case").short("i").help({ text: "ignore case distinctions in patterns and data" }), Ignore),
            (Cliff.Opt.Spec.flag("no-ignore-case").help({ text: "do not ignore case distinctions (default)" }), Respect),
        ], Respect)
    |> Cliff.with_opt(Cliff.Opt.Spec.flag("invert-match").short("v").help({ text: "select non-matching lines" }))
    |> Cliff.with_opt_help_section("Output control:")
    |> Cliff.with_opt(Cliff.Opt.Spec.value("max-count").short("m").integer().help({ text: "stop after NUM lines selected", symbol: "NUM" }))
    |> Cliff.with_opt(Cliff.Opt.Spec.values("include").help({ text: "search only files that match GLOB (a file pattern)", symbol: "GLOB" }))
    |> Cliff.with_param(Cliff.Param.Spec.values("args").optionals())

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

expect { ..base_expected, pattern_and_files: [] } == cli_grep.parse([])?
expect base_expected == cli_grep.parse(["some words"])?
expect { ..base_expected, pattern_and_files: ["some words", "f.txt"] } == cli_grep.parse(["some words", "f.txt"])?
expect { ..base_expected, regexp_type: Extended, pattern_and_files: ["some words", "f.txt"] }
    == cli_grep.parse(["-E", "some words", "f.txt"])?
expect { ..base_expected, regexp_type: Extended } == cli_grep.parse(["-E", "some words"])?
expect { ..base_expected, regexp_type: Fixed } == cli_grep.parse(["-F", "some words"])?
expect { ..base_expected, regexp_type: Basic } == cli_grep.parse(["-G", "some words"])?
expect { ..base_expected, regexp_type: Perl } == cli_grep.parse(["-P", "some words"])?
expect { ..base_expected, case: Ignore, regexp_type: Perl }
    == cli_grep.parse(["-i", "-P", "some words"])?
expect { ..base_expected, case: Ignore} == cli_grep.parse(["-i", "some words"])?
expect base_expected == cli_grep.parse(["--no-ignore-case", "some words"])?
expect { ..base_expected, invert_match: True } == cli_grep.parse(["-v", "some words"])?
expect { ..base_expected, max_count: Some(100) } == cli_grep.parse(["--max-count", "100", "some words"])?
expect { ..base_expected, include: ["inc1", "inc2"] } == cli_grep.parse(["--include=inc1", "--include=inc2", "some words"])?
