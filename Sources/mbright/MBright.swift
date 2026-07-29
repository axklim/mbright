import ArgumentParser

@main
struct MBright: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mbright",
        abstract: "Control display brightness on macOS.",
        version: "0.1.0",
        subcommands: [
            ListCommand.self,
            GetCommand.self,
            SetCommand.self,
            UpCommand.self,
            DownCommand.self,
        ],
        defaultSubcommand: ListCommand.self
    )
}
