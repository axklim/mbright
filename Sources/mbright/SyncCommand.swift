import ArgumentParser
import MBrightCore

extension SyncMode: ExpressibleByArgument {}

struct SyncCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Show or set how the other displays follow the main display.",
        discussion: """
            off: every display is adjusted on its own. \
            full: other displays are set to the main display's value. \
            relative: other displays change by the same amount as the main display. \
            Full applies at once; the setting is saved to the config file.
            """
    )

    @Argument(help: "off, full, or relative. Omit to print the current mode.")
    var mode: SyncMode?

    @OptionGroup var daemon: DaemonOptions

    func run() throws {
        // Read first so login and ui survive; only sync changes here.
        var config = try configStatus(.config, autostart: daemon.daemonAutostart).config
        if let mode {
            config.sync = mode
            config = try configStatus(.setConfig(config), autostart: daemon.daemonAutostart).config
        }
        print(syncLine(config))
    }
}
