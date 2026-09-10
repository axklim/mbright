import Foundation

/// An append-only text log under `$XDG_STATE_HOME/mbright/`, one file per
/// process, that costs nothing while it is off. Same XDG rules as the
/// socket and config: unset, empty or relative means `~/.local/state`.
///
/// Callers may log from any thread; the observer callback in the daemon
/// does not arrive on the main one.
public final class DebugLog: @unchecked Sendable {
    public static let xdgStateVariable = "XDG_STATE_HOME"

    public let url: URL
    private let lock = NSLock()
    private var handle: FileHandle?
    private let formatter: DateFormatter

    public init(url: URL) {
        self.url = url
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    public static func resolve(
        name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let base = xdgDirectory(environment[xdgStateVariable]).map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".local/state")
        return base.appendingPathComponent("mbright").appendingPathComponent("\(name).log")
    }

    public var isEnabled: Bool {
        lock.withLock { handle != nil }
    }

    /// Opens or closes the file. A file that cannot be opened leaves the
    /// log off; debug output must never take the process down.
    public func setEnabled(_ enabled: Bool) {
        lock.withLock {
            if enabled {
                guard handle == nil else { return }
                handle = open()
            } else {
                try? handle?.close()
                handle = nil
            }
        }
    }

    public func log(_ message: @autoclosure () -> String) {
        lock.withLock {
            guard let handle else { return }
            let line = "\(formatter.string(from: Date())) \(message())\n"
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    private func open() -> FileHandle? {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !manager.fileExists(atPath: url.path) {
                manager.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            return handle
        } catch {
            return nil
        }
    }

    private static func xdgDirectory(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.hasPrefix("/") else { return nil }
        return value
    }
}
