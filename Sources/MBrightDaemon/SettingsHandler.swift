import Foundation
import MBrightCore
import MBrightIPC

/// The daemon's view of the config: one in-memory copy, the file it came
/// from, and the plist derived from it. Main actor, like everything else
/// in the daemon's run loop.
@MainActor
public final class SettingsHandler {
    public private(set) var config = Config()

    private let file: ConfigFile
    private let executable: String
    private let agentURL: URL
    private let bundle: InstalledBundle?
    private let environment: [String: String]
    private let log: (String) -> Void

    public init(
        file: ConfigFile,
        executable: String,
        agentURL: URL,
        bundle: InstalledBundle?,
        environment: [String: String],
        log: @escaping (String) -> Void
    ) {
        self.file = file
        self.executable = executable
        self.agentURL = agentURL
        self.bundle = bundle
        self.environment = environment
        self.log = log
    }

    /// The daemon must come up whatever the file says, so a malformed file
    /// is logged and left in place rather than fatal or overwritten. With
    /// no file, or outside a bundle, the config defaults to login: false;
    /// reconciling that against an existing plist would delete it, so the
    /// plist is only touched at start when a file actually loaded and the
    /// daemon can act on it.
    public func start() {
        let loaded: Config?
        do {
            loaded = try file.load()
            config = loaded ?? Config()
        } catch {
            log("Warning: \(error); using defaults")
            loaded = nil
            config = Config()
        }
        guard loaded != nil, bundle != nil else { return }
        do {
            try reconcile(.start)
        } catch {
            log("Warning: could not update \(agentURL.path): \(error)")
        }
    }

    public var status: ConfigStatus {
        ConfigStatus(config: config, path: file.path, onDisk: file.exists)
    }

    /// `nil` for requests that are not about config.
    public func handle(_ request: Request) -> Response? {
        switch request {
        case .config:
            return .config(status)
        case let .setConfig(new):
            return respond { try set(new) }
        case .reloadConfig:
            return respond { try reload() }
        case .writeConfig:
            return respond { if !file.exists { try file.save(config) } }
        default:
            return nil
        }
    }

    private func respond(_ body: () throws -> Void) -> Response {
        do {
            try body()
            return .config(status)
        } catch let error as MBrightError {
            return .failure(error)
        } catch {
            return .failure(.daemonFailure("\(error)"))
        }
    }

    private func set(_ new: Config) throws {
        if new.login, bundle == nil {
            throw MBrightError.loginUnavailable(reason: "mbrightd is running from \(executable)")
        }
        try file.save(new)
        config = new
        try reconcile(.explicit, orReport: "config saved to \(file.path)")
    }

    private func reload() throws {
        config = try file.load() ?? Config()
        try reconcile(.start, orReport: "config reloaded from \(file.path)")
    }

    /// The config is already saved/reloaded by the time this runs, so a
    /// failed plist update must not read back as a failed request: it is
    /// reported as `daemonFailure`, not surfaced as the reconcile error.
    private func reconcile(_ trigger: LoginReconciler.Trigger, orReport prefix: String) throws {
        do {
            try reconcile(trigger)
        } catch {
            throw MBrightError.daemonFailure("\(prefix), but could not update \(agentURL.path): \(error)")
        }
    }

    private func reconcile(_ trigger: LoginReconciler.Trigger) throws {
        let action = LoginReconciler.action(
            config: config, bundle: bundle, environment: environment,
            existing: LaunchAgent.read(at: agentURL), trigger: trigger)
        try LoginReconciler.apply(action, at: agentURL)
    }
}
