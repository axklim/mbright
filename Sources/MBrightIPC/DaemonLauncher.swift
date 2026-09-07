import Foundation
import MBrightCore

/// Connects to `mbrightd`, starting it on demand when nothing is listening.
public enum DaemonLauncher {
    public static let daemonExecutableName = "mbrightd"

    /// Connects, spawning the daemon first if needed. Returns a connected
    /// socket descriptor the caller owns.
    public static func connect(
        path: String = SocketPath.resolve(),
        spawnIfNeeded: Bool = true,
        timeout: TimeInterval = 3
    ) throws -> Int32 {
        if let fd = try? UnixSocket.connect(path: path) { return fd }
        guard spawnIfNeeded else {
            throw MBrightError.daemonNotRunning
        }

        guard let daemon = locateDaemon() else {
            throw MBrightError.daemonUnavailable(
                reason: "\(daemonExecutableName) was not found next to this executable or on PATH")
        }
        try spawn(daemon)

        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?
        while Date() < deadline {
            do {
                return try UnixSocket.connect(path: path)
            } catch {
                lastError = error
                usleep(50_000)
            }
        }
        throw MBrightError.daemonUnavailable(
            reason: "started \(daemon) but it did not answer within \(Int(timeout))s"
                + (lastError.map { " (\($0))" } ?? ""))
    }

    /// The daemon next to the calling executable wins over one on PATH so a
    /// from-source build never silently talks to a Homebrew install.
    public static func locateDaemon(
        executableURL: URL? = Bundle.main.executableURL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        var candidates: [String] = []
        if let executableURL {
            let resolved = executableURL.resolvingSymlinksInPath()
            candidates.append(executableURL.deletingLastPathComponent().appendingPathComponent(daemonExecutableName).path)
            candidates.append(resolved.deletingLastPathComponent().appendingPathComponent(daemonExecutableName).path)
        }
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            candidates.append((String(directory) as NSString).appendingPathComponent(daemonExecutableName))
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Starts the daemon in its own session with stdio on /dev/null, so it
    /// outlives the terminal (and SIGHUP) of whatever launched it. The
    /// environment is inherited, so the daemon resolves the same
    /// `XDG_RUNTIME_DIR` as the client.
    static func spawn(_ executable: String) throws {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        for fd: Int32 in 0...2 {
            posix_spawn_file_actions_addopen(&fileActions, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0)
        }

        let arguments = [executable]
        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }

        var pid: pid_t = 0
        let code = posix_spawn(&pid, executable, &fileActions, &attributes, argv, environ)
        guard code == 0 else {
            throw MBrightError.daemonUnavailable(
                reason: "could not start \(executable): \(String(cString: strerror(code)))")
        }
    }
}
