# CliFF - Cli For Fun

An applicative commandline parser for Roc

This package aims to provide convenient parsing of command line arguments into typed and structured records.

Read the [documentation](https://oldironhorse.github.io/cliff/) and raise in [issue](https://oldironhorse.github.io/cliff/) for bugs or feature requests.

## Status

This is very much a work in progress but it should allow the building of both grep-style and git-stype CLIs.

## Example

```roc
app [main!] {
    pf: platform "<latest from https://github.com/roc-lang/basic-cli/releases>",
    cliff: "<latest from https://github.com/OldIronHorse/cliff/releases>",
}

import pf.OsStr
import pf.Stdout
import Grep

main! : List(OsStr) => Try({}, _)
main! = |argv| {
    match argv.map_try(OsStr.to_str_try) {
        Ok(args) =>
            match Grep.cli.parse(args) {
                Ok(cfg) =>
                    Stdout.line!("running... ${Str.inspect(args)} ${Str.inspect(cfg)}")
                Err(ShowHelp(text)) =>
                    Stdout.line!(text)
                Err(e) =>
                    e |> Str.inspect() |> Stdout.line!()
            }
        Err(e) =>
            e |> Str.inspect() |> Stdout.line!()
    }
}

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
```

Here's what running that look like:

```
$ roc run examples/grep.roc
running... [] { case: Respect, include: [], invert_match: False, max_count: None, pattern_and_files: [], pattern_file: None, pattern_regexp: None, regexp_type: Basic }

$ roc run examples/grep.roc -- ERROR trace.log
running... ["ERROR", "trace.log"] { case: Respect, include: [], invert_match: False, max_count: None, pattern_and_files: ["ERROR", "trace.log"], pattern_file: None, pattern_regexp: None, regexp_type: Basic }

$ roc run examples/grep.roc -- -iv ERROR trace.log
running... ["-iv", "ERROR", "trace.log"] { case: Ignore, include: [], invert_match: True, max_count: None, pattern_and_files: ["ERROR", "trace.log"], pattern_file: None, pattern_regexp: None, regexp_type: Basic }

$ roc run examples/grep.roc -- --help
grep [OPTION]... PATTERNS [FILE]...
Search for PATTERNS in each FILE.
Example: grep -i 'hello world' menu.h main.c

Pattern selection and interpretation:
-E, --extended-regexp  PATTERNS are extended regular expressions
-F, --fixed-strings    PATTERNS are strings
-G, --basic-regexp     PATTERNS are basic regular expressions (default)
-P, --perl-regexp      PATTERNS are Perl regular expressions
-e, --regexp=REGEXP    use REGEXP for matching
-f, --file=FILE        take PATTERNS from FILE
-i, --ignore-case      ignore case distinctions in patterns and data
    --no-ignore-case   do not ignore case distinctions (default)
-v, --invert-match     select non-matching lines

Output control:
-m, --max-count=NUM    stop after NUM lines selected
    --include=GLOB     search only files that match GLOB (a file pattern)

    --help             display this help text and exit

When FILE is '-', read standard input.  With no FILE, read '.' if
recursive, '-' otherwise.  With fewer than two FILEs, assume -h.
Exit status is 0 if any line is selected, 1 otherwise;
if any error occurs and -q is not given, the exit status is 2.

Report bugs to: bug-grep@gnu.org
GNU grep home page: <https://www.gnu.org/software/grep/>
General help using GNU software: <https://www.gnu.org/gethelp/>
$
```

## License

Licensed under UPL-1.0
