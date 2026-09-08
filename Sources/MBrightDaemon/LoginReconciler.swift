import Foundation
import MBrightCore

/// Decides what the login plist should look like given the config, and
/// applies it. Pure in `action` so every row of the table is testable.
///
/// On `.start` an existing plist's environment wins over the daemon's own:
/// the pinned value is the one that worked at enable time, and a daemon
/// started from a terminal with a scratch `XDG_RUNTIME_DIR` must not
/// overwrite it. `.explicit` (a setConfig) is the user asking, so there the
/// current environment is what they mean.
public enum LoginReconciler {
    public enum Trigger: Sendable {
        case start
        case explicit
    }

    public enum Action: Equatable, Sendable {
        case write(LaunchAgent)
        case remove
        case leave
    }

    public static func action(
        config: Config,
        bundle: InstalledBundle?,
        environment: [String: String],
        existing: LaunchAgent?,
        trigger: Trigger
    ) -> Action {
        guard config.login else {
            return existing == nil ? .leave : .remove
        }
        guard let bundle else { return .leave }
        let program = bundle.program(for: config)
        let current = LaunchAgent.relevantEnvironment(environment)
        switch trigger {
        case .explicit:
            return .write(LaunchAgent(program: program, environment: current))
        case .start:
            guard let existing else {
                return .write(LaunchAgent(program: program, environment: current))
            }
            if existing.program == program { return .leave }
            return .write(LaunchAgent(program: program, environment: existing.environment))
        }
    }

    public static func apply(_ action: Action, at url: URL) throws {
        switch action {
        case let .write(agent):
            try agent.write(to: url)
        case .remove:
            try LaunchAgent.remove(at: url)
        case .leave:
            break
        }
    }
}
