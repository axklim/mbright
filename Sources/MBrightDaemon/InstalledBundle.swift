import Foundation
import MBrightCore

/// The app bundle `make install` writes, found from the daemon's own path.
/// Only a daemon running from `<x>.app/Contents/Helpers/mbrightd` has a
/// stable program path a login plist can point at; a build-directory
/// daemon does not.
public struct InstalledBundle: Equatable, Sendable {
    public static let daemonName = "mbrightd"
    public static let appName = "mbright-menubar"

    public let root: URL

    public init?(daemonExecutable: String) {
        let url = URL(fileURLWithPath: daemonExecutable)
        let parts = url.pathComponents
        guard parts.count >= 4,
              parts[parts.count - 1] == Self.daemonName,
              parts[parts.count - 2] == "Helpers",
              parts[parts.count - 3] == "Contents",
              parts[parts.count - 4].hasSuffix(".app")
        else { return nil }
        root = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    public var daemon: String {
        root.appendingPathComponent("Contents/Helpers").appendingPathComponent(Self.daemonName).path
    }

    public var app: String {
        root.appendingPathComponent("Contents/MacOS").appendingPathComponent(Self.appName).path
    }

    public func program(for config: Config) -> String {
        config.ui ? app : daemon
    }
}
