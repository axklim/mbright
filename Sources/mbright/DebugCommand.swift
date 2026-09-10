import ArgumentParser
import Foundation
import MBrightCore
import MBrightIPC

enum DebugState: String, ExpressibleByArgument, CaseIterable {
    case on, off
}

struct DebugCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "debug",
        abstract: "Show or set debug logging.",
        discussion: """
            When on, mbrightd writes mbrightd.log and the menu bar app writes \
            mbright-menubar.log under $XDG_STATE_HOME/mbright (~/.local/state/mbright \
            by default). Takes effect at once in both; the setting is saved to the \
            config file.
            """
    )

    @Argument(help: "on or off. Omit to print the current state.")
    var state: DebugState?

    @OptionGroup var daemon: DaemonOptions

    func run() throws {
        // Read first so the other keys survive; only debug changes here.
        var config = try configStatus(.config, autostart: daemon.daemonAutostart).config
        if let state {
            config.debug = state == .on
            config = try configStatus(.setConfig(config), autostart: daemon.daemonAutostart).config
        }
        print(debugLine(config))
    }
}
