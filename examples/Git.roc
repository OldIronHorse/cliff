import cliff.Cli

Git := {}.{
    cli = Cli.succeed(|git_dir| |no_pager| |cmd| { git_dir, no_pager, cmd })
        .with_opt(Cli.Opt.Spec.value("git-dir")
            .default(".git")
            .symbol("PATH")
            .help("storage directory (default: .git)"))
        .with_opt(Cli.Opt.Spec.flag("no-pager"))
        .with_subcommands([
            Cli.Subcommand.command("commit", commit_cli.map(|c| Commit(c))).help("Record changes to the repository"),
            Cli.Subcommand.command("add", add_cli.map(|c| Add(c))),
            Cli.Subcommand.command("remote", remote_cli.map(|c| Remote(c))),
        ])
}

remote_cli = Cli.succeed(|cmd| { cmd })
        .with_usage(\\git remote COMMAND
                    \\Act on a remote repository
                    \\
                    )
        .with_subcommands([
            Cli.Subcommand.command("commit", commit_cli.map(|c| Commit(c))).help("Record changes to the repository"),
            Cli.Subcommand.command("add", add_cli.map(|c| Add(c))),
        ])

commit_cli = Cli.succeed(|message| |amend| { message, amend })
    .with_usage(\\git commit [OPTION]...
                \\Record changes to the repository
                \\example: git commit --message "Fix for important bug"
                \\
                )
    .with_opt(Cli.Opt.Spec.value("message"))
    .with_opt(Cli.Opt.Spec.flag("amend"))

add_cli = Cli.succeed(|name| |url| { name, url })
    .with_param(Cli.Param.Spec.value("name"))
    .with_param(Cli.Param.Spec.value("url").optional())

expect {
        git_dir: ".git",
        no_pager: False,
        cmd: Add({ name: "123.roc", url: None })
    } == Git.cli.parse(["add", "123.roc"])?

expect {
    git_dir: ".git"
    no_pager: True
    cmd: Commit({ message: Some("Initial check in"), amend: False })
} == Git.cli.parse(["--no-pager", "commit", "--message", "Initial check in"])?

expect Err(MissingSubcommand) == Git.cli.parse([])

expect Err(UnknownSubcommand("status")) == Git.cli.parse(["status"])
expect Err(UnknownOption("no-pager")) == Git.cli.parse(["commit", "--no-pager"])
expect Err(MissingValue("message")) == Git.cli.parse(["commit", "--message"])

expect {
    expected = \\    --git-dir=PATH  storage directory (default: .git)
               \\    --no-pager
               \\
               \\  commit            Record changes to the repository
               \\  add
               \\  remote
               \\
               \\    --help          display this help text and exit
               \\
    Err(ShowHelp(expected)) == Git.cli.parse(["--help"])
}

expect {
    expected = \\git commit [OPTION]...
               \\Record changes to the repository
               \\example: git commit --message "Fix for important bug"
               \\
               \\    --message
               \\    --amend
               \\
               \\    --help     display this help text and exit
               \\
    Err(ShowHelp(expected)) == Git.cli.parse(["commit", "--help"])
}

expect {
    expected = \\git remote COMMAND
               \\Act on a remote repository
               \\
               \\  commit    Record changes to the repository
               \\  add
               \\
               \\    --help  display this help text and exit
               \\
    Err(ShowHelp(expected)) == Git.cli.parse(["remote", "--help"])
}
