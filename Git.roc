import Cli

Git := {}.{
    cli = Cli.succeed(|git_dir| |no_pager| |cmd| { git_dir, no_pager, cmd })
        .with_opt(Cli.Opt.Spec.value("git-dir"))
        .with_opt(Cli.Opt.Spec.flag("no-pager"))
        .with_subcommands([
            ("commit", commit_cli.map(|c| Commit(c))),
            ("add", add_cli.map(|c| Add(c))),
        ])
}

commit_cli = Cli.succeed(|message| |amend| { message, amend })
    .with_opt(Cli.Opt.Spec.value("message"))
    .with_opt(Cli.Opt.Spec.flag("amend"))

add_cli = Cli.succeed(|name| |url| { name, url })
    .with_param(Cli.Param.Spec.value("name"))
    .with_param(Cli.Param.Spec.value("url").optional())

expect {
        git_dir: None,
        no_pager: False,
        cmd: Add({ name: "123.roc", url: None })
    } == Git.cli.parse(["add", "123.roc"])?

expect {
    git_dir: None
    no_pager: True
    cmd: Commit({ message: Some("Initial check in"), amend: False })
} == Git.cli.parse(["--no-pager", "commit", "--message", "Initial check in"])?

expect Err(MissingSubcommand) == Git.cli.parse([])

expect Err(UnknownSubcommand("status")) == Git.cli.parse(["status"])
expect Err(UnknownOption("no-pager")) == Git.cli.parse(["commit", "--no-pager"])
expect Err(MissingValue("message")) == Git.cli.parse(["commit", "--message"])
