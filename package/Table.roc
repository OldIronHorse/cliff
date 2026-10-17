# SPDX-License-Identifier: UPL-1.0
# Copyright (c) 2026 Simon Redding

## A text table formatter.
##
## Build a `Table` from one of the style constructors ([Table.plain],
## [Table.pipe] or [Table.grid]), optionally describe its columns with
## [Table.with_columns], then call [Table.format] with the rows to get back
## one string per output line.
##
## Columns are sized to fit their widest cell. Rows shorter than the table are
## padded using each column's default value, and the table grows extra unnamed
## columns if a row is wider than the columns you declared.
##
## ```roc
## expect {
##     Table.pipe
##         .with_columns([Table.column("Dog"), Table.column("Cat")])
##         .format([["one", "two"], ["five", "six"]])
##         == [
##             "| Dog  | Cat |",
##             "|:-----|:----|",
##             "| one  | two |",
##             "| five | six |",
##         ]
## }
## ```
Table :: {
    style: Style,
    columns: List(Column) ?? [],
}.{
    ## How a table is drawn.
    ##
    ## - `Plain`: columns separated by spaces, with a dashed rule under the header.
    ## - `Pipe`: Markdown-style pipe table, including alignment markers.
    ## - `Grid`: reStructuredText-style grid with a rule between every row.
    Style : [Plain, Pipe, Grid]

    ## A table drawn in the `Plain` style, with no columns declared.
    ##
    ## Without columns there is no header row, so the output is just the aligned
    ## rows.
    ##
    ## ```roc
    ## expect Table.plain.format([["one", "two"], ["five", "six"]]) == [
    ##     "one  two",
    ##     "five six",
    ## ]
    ## ```
    plain : Table
    plain = Table.{ style: Plain }

    ## A table drawn in the `Pipe` style (Markdown pipe tables), with no columns
    ## declared.
    ##
    ## ```roc
    ## expect Table.pipe.format([["one", "two"], ["five", "six"]]) == [
    ##     "| one  | two |",
    ##     "| five | six |",
    ## ]
    ## ```
    pipe : Table
    pipe = Table.{ style: Pipe }

    ## A table drawn in the `Grid` style, with a rule above, below and between
    ## every row, with no columns declared.
    ##
    ## When columns are declared, the header is separated from the body by a
    ## double (`=`) rule.
    grid : Table
    grid = Table.{ style: Grid }

    ## How the text in a column is aligned within its width.
    ##
    Alignment : [Right, Left, Centre]

    ## Describes a single column of a [Table]: its header name, its alignment and
    ## the value used to fill cells that a row leaves out.
    ##
    ## Create one with [Table.column] and refine it with [Column.align] and
    ## [Column.default].
    Column := { # TODO: type, formatting, Width : [Auto, Max(U64), Min(U64)]
        name: Str ?? "",
        align: Alignment ?? Left,
        default_value: Str ?? "",
    }.{
        ## Sets how the column's cells are aligned. Columns are `Left` aligned
        ## unless you say otherwise.
        ##
        ## ```roc
        ## Table.column("Antelope").align(Right)
        ## ```
        align : Column, Alignment -> Column
        align = |column, align| { ..column, align }

        ## Sets the value used for this column when a row has no cell for it.
        ## The default is the empty string.
        ##
        ## ```roc
        ## Table.column("Sheep").default("N/A")
        ## ```
        default : Column, Str -> Column
        default = |column, v| { ..column, default_value: v }
    }

    ## Creates a [Column] with the given header name, `Left` aligned and with an
    ## empty default value.
    ##
    ## ```roc
    ## Table.column("Dog")
    ## ```
    column : Str -> Column
    column = |name| Column.{ name }

    ## Formats `rows` as a table, returning one string per output line.
    ##
    ## Each inner list is a row of cells. Column widths are measured in UTF-8
    ## bytes, so text containing multi-byte characters may not line up.
    ##
    ## - If the table has columns, a header (and its separator) is included.
    ## - Rows shorter than the table are padded with each column's default value.
    ## - Rows wider than the declared columns get extra unnamed columns.
    ## - `Plain` output has trailing whitespace trimmed from each line.
    ##
    ## ```roc
    ## expect {
    ##     Table.plain
    ##         .with_columns([Table.column("Dog"), Table.column("Cat")])
    ##         .format([["one", "two"], ["five", "six"]])
    ##         == [
    ##             "Dog  Cat",
    ##             "---- ---",
    ##             "one  two",
    ##             "five six",
    ##         ]
    ## }
    ## ```
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
                {
                    if table.columns.is_empty()
                        []
                    else
                        [columns.map(|c| c.name), max_widths.map(|w| "-".repeat(w))]
                }.concat(rs)
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
                                        Centre => ":${"-".repeat(width)}:"
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

    ## Returns a copy of the table with its columns replaced by `columns`.
    ##
    ## The columns give the header names, alignment and default values, in
    ## left-to-right order.
    ##
    ## ```roc
    ## Table.grid.with_columns([Table.column("Dog"), Table.column("Cat")])
    ## ```
    with_columns : Table, List(Column) -> Table
    with_columns = |table, columns| { ..table, columns }
}

# Internal helper: pads or aligns one cell according to its column's alignment.
format_field : Str, U64, Table.Column -> Str
format_field = |field, width, col|
    match col.align {
        Left => pad_right(field, width)
        Right => pad_left(field, width)
        Centre => {
            len = field.count_utf8_bytes()
            pad = (width - len) / 2
            "${" ".repeat(pad)}${field}${" ".repeat(width - len - pad)}"
        }
    }

# Internal helpers: pad a string with spaces to a width (in UTF-8 bytes).
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
expect {
    expected = [
        "| Dog  | Cat | Antelope | Sheep |",
        "|:-----|:----|:--------:|:------|",
        "| one  | two |  three   | four  |",
        "| five | six |  seven   | eight |",
    ]
    actual = Table.pipe
        .with_columns([Table.column("Dog"), Table.column("Cat"), Table.column("Antelope").align(Centre), Table.column("Sheep")])
        .format([["one", "two", "three", "four"], ["five", "six", "seven", "eight"]])
    actual == expected
}
