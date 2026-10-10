app [main!] {
    pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.24.0/AEjfyaMFFbh8FJrkkHJy68riVNPr3Qp6c6PawWQjBwMH.tar.zst",
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
                Err(ShowHelp) =>
                    Stdout.line!(Grep.cli.to_help_str())
                Err(e) =>
                    e |> Str.inspect() |> Stdout.line!()
            }
        Err(e) =>
            e |> Str.inspect() |> Stdout.line!()
    }
}
