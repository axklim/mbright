import Foundation
import MBrightIPC

/// "Launch at login" for a bare executable. `SMAppService` needs an app
/// bundle, so this writes a LaunchAgent plist instead. The file is only
/// written or removed, never bootstrapped: loading it while the app is
/// already running would start a second copy, and unloading it would kill
/// a copy launchd started. Changes take effect at the next login.
public struct LaunchAgent: Sendable {
    public static let label = "com.axklim.mbright.menubar"

    public let executablePath: String
    public let fileURL: URL
    /// Environment launchd should hand the app. launchd never inherits the
    /// user's shell environment, so an `XDG_RUNTIME_DIR` exported in
    /// `.zshrc` would be invisible to an app started at login, and the app
    /// would resolve a different socket than the CLI in a terminal. The
    /// value in force when Launch at login is enabled is baked in here.
    public let environment: [String: String]

    public init(executablePath: String, fileURL: URL = LaunchAgent.defaultFileURL,
                environment: [String: String] = [:]) {
        self.executablePath = executablePath
        self.fileURL = fileURL
        self.environment = environment
    }

    /// The subset of `environment` that changes where mbright puts files:
    /// only a valid XDG runtime dir, and only if one is set.
    public static func relevantEnvironment(_ environment: [String: String]) -> [String: String] {
        guard let runtime = SocketPath.xdgDirectory(environment[SocketPath.xdgRuntimeVariable]) else { return [:] }
        return [SocketPath.xdgRuntimeVariable: runtime]
    }

    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    public var plist: [String: Any] {
        var plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [executablePath],
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

    public var isEnabled: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try plistData().write(to: fileURL, options: .atomic)
        } else if isEnabled {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
