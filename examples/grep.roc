# SPDX-License-Identifier: UPL-1.0
# Copyright (c) 2026 Simon Redding
app [main!] {
    pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
    cliff: "../package/main.roc",
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
