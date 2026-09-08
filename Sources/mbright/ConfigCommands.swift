import ArgumentParser
import Foundation
import MBrightCore
import MBrightIPC

func loginLine(_ config: Config) -> String {
    guard config.login else { return "login: disabled" }
    return "login: enabled, starts \(config.ui ? "the menu bar app" : "mbrightd only")"
}

func abbreviated(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

func describe(_ status: ConfigStatus) -> String {
    let path = abbreviated(status.path)
    return """
        \(path)\(status.onDisk ? "" : " (not written yet)")
        \(loginLine(status.config))
        ui: \(status.config.ui ? "menu bar app" : "mbrightd only")
        """
}

func configStatus(_ request: Request, autostart: Bool) throws -> ConfigStatus {
    let response = try perform(request, autostart: autostart)
    guard case let .config(status) = response else { throw unexpected(response) }
    return status
}

struct DaemonEnableLogin: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enable-login",
        abstract: "Start mbright at login. Takes effect at the next login."
    )

    @Flag(name: .customLong("no-ui"), help: "Start mbrightd alone instead of the menu bar app.")
    var noUI = false

    @OptionGroup var daemon: DaemonOptions

    func run() throws {
        let status = try configStatus(.setConfig(Config(login: true, ui: !noUI)), autostart: daemon.daemonAutostart)
        print(loginLine(status.config))
    }
}

struct DaemonDisableLogin: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable-login",
        abstract: "Stop starting mbright at login."
    )

    @OptionGroup var daemon: DaemonOptions

    func run() throws {
        // Read first so the ui key survives; only login changes here.
        var config = try configStatus(.config, autostart: daemon.daemonAutostart).config
        config.login = false
        let status = try configStatus(.setConfig(config), autostart: daemon.daemonAutostart)
        print(loginLine(status.config))
    }
}

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Show, create, or reload the config file.",
        subcommands: [ConfigShow.self, ConfigInit.self, ConfigReload.self],
        defaultSubcommand: ConfigShow.self
    )
}

struct ConfigShow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Print the config path and the settings mbrightd holds."
    )

    @OptionGroup var daemon: DaemonOptions

    func run() throws {
        print(describe(try configStatus(.config, autostart: daemon.daemonAutostart)))
    }
}

struct ConfigInit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Write the config file from the current settings, if it does not exist."
    )

    @OptionGroup var daemon: DaemonOptions

    func run() throws {
        let before = try configStatus(.config, autostart: daemon.daemonAutostart)
        let path = abbreviated(before.path)
        guard !before.onDisk else {
            print("\(path) already exists")
            return
        }
        _ = try configStatus(.writeConfig, autostart: daemon.daemonAutostart)
        print("wrote \(path)")
    }
}

struct ConfigReload: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reload",
        abstract: "Re-read the config file and update the login LaunchAgent."
    )

    @OptionGroup var daemon: DaemonOptions

    func run() throws {
        print(describe(try configStatus(.reloadConfig, autostart: daemon.daemonAutostart)))
    }
}
