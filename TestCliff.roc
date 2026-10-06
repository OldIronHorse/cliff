import Cliff

TestCliff := {}.{}

cli_grep = Cliff.succeed(|regexp_type| |case| |pattern| |files|
                         { regexp_type, case, pattern, files })
    |> Cliff.with_opt_group(
        [
            (Cliff.Opt.Spec.flag("extended-regexp").short("E"), Extended),
            (Cliff.Opt.Spec.flag("fixed-strings").short("F"), Fixed),
            (Cliff.Opt.Spec.flag("basic-regexp").short("G"), Basic),
            (Cliff.Opt.Spec.flag("perl-regexp").short("P"), Perl),
        ], Basic)
    |> Cliff.with_opt_group(
        [
            (Cliff.Opt.Spec.flag("ignore-case").short("i"), Ignore),
            (Cliff.Opt.Spec.flag("no-ignore-case"), Respect),
        ], Respect)
    |> Cliff.with_param(Cliff.Param.Spec.value("pattern"))
    |> Cliff.with_param(Cliff.Param.Spec.values("files").optionals())

base_expected = {
    regexp_type: Basic,
    pattern: "some words",
    case: Respect,
    files: []
}

expect base_expected == cli_grep.parse(["some words"])?
expect { ..base_expected, files: ["f.txt"] } == cli_grep.parse(["some words", "f.txt"])?
expect { ..base_expected, regexp_type: Extended, files: ["f.txt"] }
    == cli_grep.parse(["-E", "some words", "f.txt"])?
expect { ..base_expected, regexp_type: Extended } == cli_grep.parse(["-E", "some words"])?
expect { ..base_expected, regexp_type: Fixed } == cli_grep.parse(["-F", "some words"])?
expect { ..base_expected, regexp_type: Basic } == cli_grep.parse(["-G", "some words"])?
expect { ..base_expected, regexp_type: Perl } == cli_grep.parse(["-P", "some words"])?
expect { ..base_expected, case: Ignore, regexp_type: Perl }
    == cli_grep.parse(["-i", "-P", "some words"])?
expect { ..base_expected, case: Ignore} == cli_grep.parse(["-i", "some words"])?
expect base_expected == cli_grep.parse(["--no-ignore-case", "some words"])?
expect Err(MissingArguments(["pattern"])) == cli_grep.parse([])
