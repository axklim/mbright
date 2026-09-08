import Foundation
import MBrightIPC

/// The one LaunchAgent mbright writes. Only written or removed, never
/// bootstrapped: loading it while the program is already running would
/// start a second copy, and unloading would kill a copy launchd started.
/// No `KeepAlive`, so Quit or `daemon stop` ends the job until next login.
public struct LaunchAgent: Equatable, Sendable {
    public static let label = "com.axklim.mbright"

    public let program: String
    /// launchd never inherits the shell environment, so the
    /// `XDG_RUNTIME_DIR` and `XDG_CONFIG_HOME` in force are pinned here or
    /// the login-started process would resolve a different socket or
    /// config file than the CLI.
    public let environment: [String: String]

    public init(program: String, environment: [String: String] = [:]) {
        self.program = program
        self.environment = environment
    }

    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    /// The subset of `environment` that changes where mbright puts files:
    /// the runtime dir for the socket and the config dir for the config
    /// file, each pinned only when set to a valid (non-empty, absolute) path.
    public static func relevantEnvironment(_ environment: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        if let runtime = SocketPath.xdgDirectory(environment[SocketPath.xdgRuntimeVariable]) {
            result[SocketPath.xdgRuntimeVariable] = runtime
        }
        if let config = SocketPath.xdgDirectory(environment[ConfigFile.xdgConfigVariable]) {
            result[ConfigFile.xdgConfigVariable] = config
        }
        return result
    }

    public var plist: [String: Any] {
        var plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [program],
            "RunAtLoad": true,
        ]
        if !environment.isEmpty {
            plist["EnvironmentVariables"] = environment
        }
        return plist
    }

    public func plistData() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// `nil` for a missing file, an unparseable one, or one with another
    /// label; those are not ours to reason about.
    public static func read(at url: URL) -> LaunchAgent? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["Label"] as? String == label,
              let program = (plist["ProgramArguments"] as? [String])?.first
        else { return nil }
        return LaunchAgent(program: program, environment: plist["EnvironmentVariables"] as? [String: String] ?? [:])
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plistData().write(to: url, options: .atomic)
    }

    public static func remove(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
