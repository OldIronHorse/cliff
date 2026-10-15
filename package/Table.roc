Table :: {
    style: Style,
    headers: List(Str) ?? [],
}.{
    Style : [Plain, Pipe, Grid]

    plain : Table
    plain = Table.{ style: Plain }

    pipe : Table
    pipe = Table.{ style: Pipe }

    format : Table, List(List(Str)) -> List(Str)
    format = |grid, rows| {
        max_widths = rows
            .prepend(grid.headers)
            .map(|row| row.map(Str.count_utf8_bytes))
            .fold([], |mws, row|
                    mws.map2(row, U64.max)
                        .concat(mws.drop_first(row.len()))
                        .concat(row.drop_first(mws.len())))
        match grid.style {
            Plain =>
                (if grid.headers.is_empty() [] else [grid.headers, max_widths.map(|w| "-".repeat(w))])
                    .concat(rows)
                    .map(|row| row.map2(max_widths, |field, max_width| field |> pad_right(max_width)))
                    .map(|row|
                        row |> Str.join_with(" ")
                            .trim_end())
            Pipe => {
                {
                    if grid.headers.is_empty()
                        []
                    else
                        [
                            grid.headers
                                .map2(max_widths, |field, max_width| field |> pad_right(max_width))
                                |> Str.join_with(" | ")
                                .with_prefix("| ")
                                .concat(" |"),
                            "|:${max_widths.map(|w| "-".repeat(w)) |> Str.join_with("-|:")}-|",
                        ]
                }.concat(rows.map(|row|
                    row.map2(max_widths, |field, max_width|
                        field
                            |> pad_right(max_width)))
                            .map(|row| "| ${row |> Str.join_with(" | ")} |"))
            }
            _ => { crash "not implemented" }
        }
    }

    with_headers : Table, List(Str) -> Table
    with_headers = |grid, headers| { ..grid, headers }
}

pad_right = |s, w| "${s}${" ".repeat(w - s.count_utf8_bytes())}"

expect "one " == pad_right("one", 4)

expect ["one two three four"] == Table.plain.format([["one", "two", "three", "four"]])

expect {
    [
        "one  two three four",
        "five six seven eight",
    ] == Table.plain.format([["one", "two", "three", "four"], ["five", "six", "seven", "eight"]])
}

expect {
    [
        "| one  | two | three | four  |",
        "| five | six | seven | eight |",
    ] == Table.pipe.format([["one", "two", "three", "four"], ["five", "six", "seven", "eight"]])
}

expect {
    expected = [
        "-E, --extended-regexp  PATTERNS are extended regular expressions",
        "-f, --file=FILE        take PATTERNS from FILE",
        "    --max-count=NUM    stop after NUM lines selected",
        "",
        "    --help             display this help text and exit",
    ]
    actual = Table.plain.format([
        ["-E,", "--extended-regexp", " PATTERNS are extended regular expressions"],
        ["-f,", "--file=FILE", " take PATTERNS from FILE"],
        ["", "--max-count=NUM", " stop after NUM lines selected"],
        [""],
        ["", "--help", " display this help text and exit"],
    ])
    actual == expected
}

expect {
    expected = [
        "Dog  Cat Antelope Sheep",
        "---- --- -------- -----",
        "one  two three    four",
        "five six seven    eight",
    ]
    actual = Table.plain
        .with_headers(["Dog", "Cat", "Antelope", "Sheep"])
        .format([["one", "two", "three", "four"], ["five", "six", "seven", "eight"]])
    actual == expected
}

expect {
    expected = [
        "| Dog  | Cat | Antelope | Sheep |",
        "|:-----|:----|:---------|:------|",
        "| one  | two | three    | four  |",
        "| five | six | seven    | eight |",
    ]
    actual = Table.pipe
        .with_headers(["Dog", "Cat", "Antelope", "Sheep"])
        .format([["one", "two", "three", "four"], ["five", "six", "seven", "eight"]])
    actual == expected
}
