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
    private let agentURL: URL
    private let bundle: InstalledBundle?
    private let environment: [String: String]
    private let log: (String) -> Void

    public init(
        file: ConfigFile,
        agentURL: URL,
        bundle: InstalledBundle?,
        environment: [String: String],
        log: @escaping (String) -> Void
    ) {
        self.file = file
        self.agentURL = agentURL
        self.bundle = bundle
        self.environment = environment
        self.log = log
    }

    /// The daemon must come up whatever the file says, so a malformed file
    /// is logged and left in place rather than fatal or overwritten.
    public func start() {
        do {
            config = try file.load() ?? Config()
        } catch {
            log("Warning: \(error); using defaults")
            config = Config()
        }
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
            throw MBrightError.loginUnavailable(reason: "mbrightd is running from \(CommandLine.arguments[0])")
        }
        try file.save(new)
        config = new
        try reconcile(.explicit)
    }

    private func reload() throws {
        config = try file.load() ?? Config()
        try reconcile(.start)
    }

    private func reconcile(_ trigger: LoginReconciler.Trigger) throws {
        let action = LoginReconciler.action(
            config: config, bundle: bundle, environment: environment,
            existing: LaunchAgent.read(at: agentURL), trigger: trigger)
        try LoginReconciler.apply(action, at: agentURL)
    }
}
