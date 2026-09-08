import Foundation
import Testing
@testable import MBrightCore
@testable import MBrightDaemon

private let bundle = InstalledBundle(daemonExecutable: "/A/mbright.app/Contents/Helpers/mbrightd")!
private let appAgent = LaunchAgent(program: "/A/mbright.app/Contents/MacOS/mbright-menubar")
private let pinned = LaunchAgent(program: "/A/mbright.app/Contents/MacOS/mbright-menubar",
                                 environment: ["XDG_RUNTIME_DIR": "/run/user/501"])

@Test func loginOffRemovesAnExistingPlistAndLeavesNothingOtherwise() {
    let off = Config(login: false, ui: true)
    for trigger in [LoginReconciler.Trigger.start, .explicit] {
        #expect(LoginReconciler.action(config: off, bundle: bundle, environment: [:], existing: appAgent, trigger: trigger) == .remove)
        #expect(LoginReconciler.action(config: off, bundle: bundle, environment: [:], existing: nil, trigger: trigger) == .leave)
        // Turning login off must work even outside a bundle.
        #expect(LoginReconciler.action(config: off, bundle: nil, environment: [:], existing: appAgent, trigger: trigger) == .remove)
    }
}

@Test func explicitEnableWritesWithTheCurrentEnvironment() {
    let on = Config(login: true, ui: true)
    let env = ["XDG_RUNTIME_DIR": "/run/user/501", "PATH": "/bin"]
    #expect(LoginReconciler.action(config: on, bundle: bundle, environment: env, existing: nil, trigger: .explicit) == .write(pinned))
    // Even when the plist already matches: the user asked, the environment wins.
    #expect(LoginReconciler.action(config: on, bundle: bundle, environment: [:], existing: pinned, trigger: .explicit) == .write(appAgent))
}

@Test func startWritesOnlyWhenMissingOrPointingElsewhere() {
    let on = Config(login: true, ui: true)
    let scratch = ["XDG_RUNTIME_DIR": "/tmp/scratch"]
    #expect(LoginReconciler.action(config: on, bundle: bundle, environment: scratch, existing: nil, trigger: .start)
        == .write(LaunchAgent(program: appAgent.program, environment: scratch)))
    // Same program: leave it, even though the scratch env differs.
    #expect(LoginReconciler.action(config: on, bundle: bundle, environment: scratch, existing: pinned, trigger: .start) == .leave)
    // Different program (ui flipped by a hand edit, or the bundle moved): rewrite, keep the pinned env.
    let headless = Config(login: true, ui: false)
    #expect(LoginReconciler.action(config: headless, bundle: bundle, environment: scratch, existing: pinned, trigger: .start)
        == .write(LaunchAgent(program: bundle.daemon, environment: pinned.environment)))
}

@Test func loginOnOutsideABundleIsLeftAlone() {
    let on = Config(login: true, ui: true)
    #expect(LoginReconciler.action(config: on, bundle: nil, environment: [:], existing: nil, trigger: .start) == .leave)
    #expect(LoginReconciler.action(config: on, bundle: nil, environment: [:], existing: appAgent, trigger: .start) == .leave)
    #expect(LoginReconciler.action(config: on, bundle: nil, environment: [:], existing: nil, trigger: .explicit) == .leave)
}

@Test func applyWritesRemovesAndLeaves() throws {
    let dir = temporaryDirectory("reconcile")
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("a.plist")
    try LoginReconciler.apply(.write(pinned), at: url)
    #expect(LaunchAgent.read(at: url) == pinned)
    try LoginReconciler.apply(.leave, at: url)
    #expect(LaunchAgent.read(at: url) == pinned)
    try LoginReconciler.apply(.remove, at: url)
    #expect(LaunchAgent.read(at: url) == nil)
    try LoginReconciler.apply(.remove, at: url)
}
