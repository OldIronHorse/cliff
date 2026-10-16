Table :: {
    style: Style,
    columns: List(Column) ?? [],
}.{
    Style : [Plain, Pipe, Grid]

    plain : Table
    plain = Table.{ style: Plain }

    pipe : Table
    pipe = Table.{ style: Pipe }

    grid : Table
    grid = Table.{ style: Grid }

    Alignment : [Right, Left, Centre]
    Column := { # TODO: type, formatting, Width : [Auto, Max(U64), Min(U64)]
        name: Str ?? "",
        align: Alignment ?? Left,
        default_value: Str ?? "",
    }.{
        align : Column, Alignment -> Column
        align = |column, align| { ..column, align }

        default : Column, Str -> Column
        default = |column, v| { ..column, default_value: v }
    }

    column : Str -> Column
    column = |name| Column.{ name }

    format : Table, List(List(Str)) -> List(Str)
    format = |table, rows| {
        max_widths = rows
            .prepend(table.columns.map(|c| c.name))
            .map(|row| row.map(Str.count_utf8_bytes))
            .fold([], |mws, row|
                    mws.map2(row, U64.max)
                        .concat(mws.drop_first(row.len()))
                        .concat(row.drop_first(mws.len())))
        columns = table.columns.concat(List.repeat(Column.{}, max_widths.len() - table.columns.len()))
        rs = rows.map(|row| row.concat(columns.drop_first(row.len()).map(|c| c.default_value)))
        match table.style {
            Plain =>
                (if table.columns.is_empty() [] else [columns.map(|c| c.name), max_widths.map(|w| "-".repeat(w))])
                    .concat(rs)
                    .map(|row|
                        row.map3(max_widths, columns, format_field))
                    .map(|row|
                        row |> Str.join_with(" ")
                            .trim_end())
            Pipe => {
                {
                    if table.columns.is_empty()
                        []
                    else
                        [
                            columns
                                .map2(max_widths, |col, max_width| col.name |> pad_right(max_width))
                                |> Str.join_with(" | ")
                                .with_prefix("| ")
                                .concat(" |"),
                            columns
                                .map2(max_widths, |col, width| 
                                    match col.align {
                                        Left => ":${"-".repeat(width + 1)}"
                                        Right => "${"-".repeat(width + 1)}:"
                                        Centre => "${"-".repeat(width + 2)}"
                                    })
                                |> Str.join_with("|")
                                .with_prefix("|")
                                .concat("|"),
                        ]
                }.concat(rs.map(|row|
                    row.map3(max_widths, columns, format_field))
                        .map(|row| "| ${row |> Str.join_with(" | ")} |"))
            }
            Grid => {
                bar = "+-${max_widths.map(|w| "-".repeat(w)) |> Str.join_with("-+-")}-+"
                {
                    if table.columns.is_empty()
                        []
                    else
                        [
                            "| ${table.columns.map2(max_widths, |col, max_width| col.name |> pad_right(max_width)) |> Str.join_with(" | ")} |",
                            "+=${max_widths.map(|w| "=".repeat(w)) |> Str.join_with("=+=")}=+"
                        ]
                }.concat(rs
                    .map(|row| "| ${row.map2(max_widths, |field, max_width| field |> pad_right(max_width)) |> Str.join_with(" | ")} |")
                    .intersperse(bar))
                .prepend(bar)
                .append(bar)
            }
        }
    }

    with_columns : Table, List(Column) -> Table
    with_columns = |table, columns| { ..table, columns }
}

format_field : Str, U64, Table.Column -> Str
format_field = |field, width, col|
    match col.align {
        Left => pad_right(field, width)
        Right => pad_left(field, width)
        Centre => { crash "not implemented" }
    }

pad_right = |s, w| "${s}${" ".repeat(w - s.count_utf8_bytes())}"
pad_left = |s, w| "${" ".repeat(w - s.count_utf8_bytes())}${s}"

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
        .with_columns([Table.column("Dog"), Table.column("Cat"), Table.column("Antelope"), Table.column("Sheep")])
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
        .with_columns([Table.column("Dog"), Table.column("Cat"), Table.column("Antelope"), Table.column("Sheep")])
        .format([["one", "two", "three", "four"], ["five", "six", "seven", "eight"]])
    actual == expected
}

expect {
    expected = [
        "| Dog  | Cat | Antelope | Sheep |",
        "|:-----|:----|:---------|:------|",
        "| one  | two |          |       |",
        "| five | six | seven    | eight |",
    ]
    actual = Table.pipe
        .with_columns([Table.column("Dog"), Table.column("Cat"), Table.column("Antelope"), Table.column("Sheep")])
        .format([["one", "two"], ["five", "six", "seven", "eight"]])
    actual == expected
}

expect {
    expected = [
        "| Dog  | Cat | Antelope | Sheep |",
        "|:-----|:----|:---------|:------|",
        "| one  | two |          | N/A   |",
        "| five | six | seven    | eight |",
    ]
    actual = Table.pipe
        .with_columns([Table.column("Dog"), Table.column("Cat"), Table.column("Antelope"), Table.column("Sheep").default("N/A")])
        .format([["one", "two"], ["five", "six", "seven", "eight"]])
    actual == expected
}

expect {
    expected = [
        "+------+-----+----------+-------+",
        "| Dog  | Cat | Antelope | Sheep |",
        "+======+=====+==========+=======+",
        "| one  | two | three    | four  |",
        "+------+-----+----------+-------+",
        "| five | six | seven    | eight |",
        "+------+-----+----------+-------+",
    ]
    actual = Table.grid
        .with_columns([Table.column("Dog"), Table.column("Cat"), Table.column("Antelope"), Table.column("Sheep")])
        .format([["one", "two", "three", "four"], ["five", "six", "seven", "eight"]])
    actual == expected
}

expect {
    expected = [
        "Dog  Cat Antelope Sheep",
        "---- --- -------- -----",
        "one  two    three four",
        "five six    seven eight",
    ]
    actual = Table.plain
        .with_columns([Table.column("Dog"), Table.column("Cat"), Table.column("Antelope").align(Right), Table.column("Sheep")])
        .format([["one", "two", "three", "four"], ["five", "six", "seven", "eight"]])
    actual == expected
}

expect {
    expected = [
        "| Dog  | Cat | Antelope | Sheep |",
        "|:-----|:----|---------:|:------|",
        "| one  | two |    three | four  |",
        "| five | six |    seven | eight |",
    ]
    actual = Table.pipe
        .with_columns([Table.column("Dog"), Table.column("Cat"), Table.column("Antelope").align(Right), Table.column("Sheep")])
        .format([["one", "two", "three", "four"], ["five", "six", "seven", "eight"]])
    actual == expected
}
