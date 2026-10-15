Grid := { separator: Str ?? " " }.{
    format : Grid, List(List(Str)) -> List(Str)
    format = |grid, rows| {
        max_widths = rows
            .map(|row| row.map(Str.count_utf8_bytes))
            .fold([], |mws, row|
                    mws.map2(row, U64.max)
                        .concat(mws.drop_first(row.len()))
                        .concat(row.drop_first(mws.len())))
        rows.map(|row| row.map2(max_widths, |field, max_width| field |> pad_right(max_width)))
            .map(|row| row |> Str.join_with(grid.separator)
            .trim_end())
    }

    with_column_sep = |grid, sep| { ..grid, separator: sep }
}

pad_right = |s, w| "${s}${" ".repeat(w - s.count_utf8_bytes())}"

expect "one " == pad_right("one", 4)

expect ["one two three four"] == Grid.{}.format([["one", "two", "three", "four"]])
expect {
    [
        "one  two three four",
        "five six seven eight",
    ] == Grid.{}.format([["one", "two", "three", "four"], ["five", "six", "seven", "eight"]])
}
expect {
    [
        "one |two|three|four",
        "five|six|seven|eight",
    ] == Grid.{}.with_column_sep("|").format([["one", "two", "three", "four"], ["five", "six", "seven", "eight"]])
}

expect {
    expected = [
        "-E, --extended-regexp  PATTERNS are extended regular expressions",
        "-f, --file=FILE        take PATTERNS from FILE",
        "    --max-count=NUM    stop after NUM lines selected",
        "",
        "    --help             display this help text and exit",
    ]
    actual = Grid.{}.format([
        ["-E,", "--extended-regexp", " PATTERNS are extended regular expressions"],
        ["-f,", "--file=FILE", " take PATTERNS from FILE"],
        ["", "--max-count=NUM", " stop after NUM lines selected"],
        [""],
        ["", "--help", " display this help text and exit"],
    ])
    actual == expected
}
