import Foundation
import MBrightCore
import MBrightIPC

/// `$XDG_CONFIG_HOME/mbright/config.json`. Same XDG rules as the socket:
/// unset, empty or relative means the default `~/.config`.
public struct ConfigFile: Sendable {
    public static let xdgConfigVariable = "XDG_CONFIG_HOME"
    public static let fileName = "config.json"

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let base = SocketPath.xdgDirectory(environment[xdgConfigVariable]).map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".config")
        return base.appendingPathComponent(SocketPath.applicationDirectory).appendingPathComponent(fileName)
    }

    public var path: String { url.path }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// `nil` when there is no file. A file that cannot be read or parsed is
    /// `MBrightError.configInvalid`, never silently defaulted.
    public func load() throws -> Config? {
        guard exists else { return nil }
        do {
            return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        } catch {
            throw MBrightError.configInvalid(path: url.path, reason: "\(error)")
        }
    }

    public func save(_ config: Config) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(config)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }
}
