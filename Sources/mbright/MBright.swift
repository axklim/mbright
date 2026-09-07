import ArgumentParser
import MBrightCore

@main
struct MBright: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mbright",
        abstract: "Control display brightness on macOS.",
        version: Version.current,
        subcommands: [
            ListCommand.self,
            GetCommand.self,
            SetCommand.self,
            UpCommand.self,
            DownCommand.self,
            DaemonCommand.self,
        ],
        defaultSubcommand: ListCommand.self
    )
}
