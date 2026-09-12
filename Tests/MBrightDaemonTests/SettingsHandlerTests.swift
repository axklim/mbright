import Foundation
import Testing
@testable import MBrightCore
@testable import MBrightDaemon
@testable import MBrightIPC

private let bundle = InstalledBundle(daemonExecutable: "/A/mbright.app/Contents/Helpers/mbrightd")!

private struct Sandbox {
    let dir: URL
    let file: ConfigFile
    let agentURL: URL

    init(_ name: String) {
        dir = temporaryDirectory(name)
        file = ConfigFile(url: dir.appendingPathComponent("config.json"))
        agentURL = dir.appendingPathComponent("agent.plist")
    }

    @MainActor
    func handler(bundle: InstalledBundle? = bundle, environment: [String: String] = [:],
                 agentURL: URL? = nil, log: @escaping (String) -> Void = { _ in }) -> SettingsHandler {
        SettingsHandler(
            file: file, executable: "/build/debug/mbrightd", agentURL: agentURL ?? self.agentURL,
            bundle: bundle, environment: environment, log: log)
    }

    func remove() { try? FileManager.default.removeItem(at: dir) }
}

@MainActor @Test func startWithNoFileUsesDefaultsAndWritesNothing() {
    let box = Sandbox("settings")
    defer { box.remove() }
    let handler = box.handler()
    handler.start()
    #expect(handler.config == Config())
    #expect(box.file.exists == false)
    #expect(LaunchAgent.read(at: box.agentURL) == nil)
    #expect(handler.handle(.config) == .config(ConfigStatus(config: Config(), path: box.file.path, onDisk: false)))
}

@MainActor @Test func startWithMalformedFileLogsAndUsesDefaults() throws {
    let box = Sandbox("settings")
    defer { box.remove() }
    try Data("{".utf8).write(to: box.file.url)
    var lines: [String] = []
    let handler = box.handler { lines.append($0) }
    handler.start()
    #expect(handler.config == Config())
    #expect(lines.count == 1)
    #expect(lines.first?.contains(box.file.path) == true)
    // Left alone until the next setConfig.
    #expect(try String(contentsOf: box.file.url, encoding: .utf8) == "{")
}

@MainActor @Test func startReconcilesFromTheFile() throws {
    let box = Sandbox("settings")
    defer { box.remove() }
    try box.file.save(Config(login: true, ui: false))
    let handler = box.handler(environment: ["XDG_RUNTIME_DIR": "/run/user/501"])
    handler.start()
    #expect(LaunchAgent.read(at: box.agentURL) == LaunchAgent(program: bundle.daemon, environment: ["XDG_RUNTIME_DIR": "/run/user/501"]))
}

@MainActor @Test func startWithNoFileLeavesAnExistingPlistAlone() throws {
    let box = Sandbox("settings")
    defer { box.remove() }
    try LaunchAgent(program: "/old").write(to: box.agentURL)
    let handler = box.handler()
    handler.start()
    #expect(LaunchAgent.read(at: box.agentURL) == LaunchAgent(program: "/old"))
    #expect(handler.config == Config())
}

@MainActor @Test func startOutsideABundleLeavesThePlistAlone() throws {
    let box = Sandbox("settings")
    defer { box.remove() }
    try box.file.save(Config(login: false, ui: true))
    try LaunchAgent(program: "/old").write(to: box.agentURL)
    let handler = box.handler(bundle: nil)
    handler.start()
    #expect(LaunchAgent.read(at: box.agentURL) == LaunchAgent(program: "/old"))
}

@MainActor @Test func setConfigSavesReconcilesAndReplies() throws {
    let box = Sandbox("settings")
    defer { box.remove() }
    let handler = box.handler()
    handler.start()
    let on = Config(login: true, ui: true)
    #expect(handler.handle(.setConfig(on)) == .config(ConfigStatus(config: on, path: box.file.path, onDisk: true)))
    #expect(try box.file.load() == on)
    #expect(LaunchAgent.read(at: box.agentURL) == LaunchAgent(program: bundle.app))

    let off = Config(login: false, ui: true)
    #expect(handler.handle(.setConfig(off)) == .config(ConfigStatus(config: off, path: box.file.path, onDisk: true)))
    #expect(LaunchAgent.read(at: box.agentURL) == nil)
}

@MainActor @Test func enablingLoginOutsideABundleFailsWithoutWriting() {
    let box = Sandbox("settings")
    defer { box.remove() }
    let handler = box.handler(bundle: nil)
    handler.start()
    let response = handler.handle(.setConfig(Config(login: true, ui: true)))
    guard case let .failure(error) = response, case .loginUnavailable = error else {
        Issue.record("expected loginUnavailable, got \(String(describing: response))")
        return
    }
    #expect(error.description.contains("/build/debug/mbrightd"))
    #expect(handler.config == Config())
    #expect(box.file.exists == false)
}

@MainActor @Test func disablingLoginOutsideABundleStillSavesAndRemoves() throws {
    let box = Sandbox("settings")
    defer { box.remove() }
    try LaunchAgent(program: "/old").write(to: box.agentURL)
    let handler = box.handler(bundle: nil)
    handler.start()
    let off = Config(login: false, ui: false)
    #expect(handler.handle(.setConfig(off)) == .config(ConfigStatus(config: off, path: box.file.path, onDisk: true)))
    #expect(try box.file.load() == off)
    #expect(LaunchAgent.read(at: box.agentURL) == nil)
}

@MainActor @Test func reloadPicksUpAHandEditAndRejectsAMalformedOne() throws {
    let box = Sandbox("settings")
    defer { box.remove() }
    let handler = box.handler()
    handler.start()
    try Data(#"{"login": true, "ui": false}"#.utf8).write(to: box.file.url)
    let edited = Config(login: true, ui: false)
    #expect(handler.handle(.reloadConfig) == .config(ConfigStatus(config: edited, path: box.file.path, onDisk: true)))
    #expect(LaunchAgent.read(at: box.agentURL)?.program == bundle.daemon)

    try Data("{".utf8).write(to: box.file.url)
    let response = handler.handle(.reloadConfig)
    guard case let .failure(error) = response, case .configInvalid = error else {
        Issue.record("expected configInvalid, got \(String(describing: response))")
        return
    }
    #expect(handler.config == edited)
}

@MainActor @Test func reloadWithTheFileDeletedFallsBackToDefaults() throws {
    let box = Sandbox("settings")
    defer { box.remove() }
    try box.file.save(Config(login: true, ui: true))
    let handler = box.handler()
    handler.start()
    #expect(LaunchAgent.read(at: box.agentURL) != nil)
    try FileManager.default.removeItem(at: box.file.url)
    #expect(handler.handle(.reloadConfig) == .config(ConfigStatus(config: Config(), path: box.file.path, onDisk: false)))
    #expect(LaunchAgent.read(at: box.agentURL) == nil)
}

@MainActor @Test func writeConfigCreatesOnceAndNeverOverwrites() throws {
    let box = Sandbox("settings")
    defer { box.remove() }
    let handler = box.handler()
    handler.start()
    #expect(handler.handle(.writeConfig) == .config(ConfigStatus(config: Config(), path: box.file.path, onDisk: true)))
    #expect(try box.file.load() == Config())

    try Data(#"{"login": true}"#.utf8).write(to: box.file.url)
    #expect(handler.handle(.writeConfig) == .config(ConfigStatus(config: Config(), path: box.file.path, onDisk: true)))
    #expect(try box.file.load() == Config(login: true, ui: true))
    #expect(LaunchAgent.read(at: box.agentURL) == nil)
}

@MainActor @Test func updateConfigKeepsSetKeysAddsMissingOnesAndDropsUnknownOnes() throws {
    let box = Sandbox("settings")
    defer { box.remove() }
    let handler = box.handler()
    handler.start()
    try Data(#"{"sync": "relative", "hotkeys": [], "retired": 1}"#.utf8).write(to: box.file.url)
    var changes: [Config] = []
    handler.onChange = { changes.append($0) }

    let expected = Config(sync: .relative, hotkeys: [])
    #expect(handler.handle(.updateConfig) == .config(ConfigStatus(config: expected, path: box.file.path, onDisk: true)))
    #expect(handler.config == expected)
    #expect(changes == [expected])

    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: box.file.url)) as? [String: Any]
    #expect(object?.keys.sorted() == ["debug", "hotkeys", "login", "sync", "ui"])
    #expect(object?["sync"] as? String == "relative")
    #expect((object?["hotkeys"] as? [Any])?.isEmpty == true)
    #expect(object?["login"] as? Bool == false)
}

@MainActor @Test func updateConfigWithNoFileWritesTheCurrentConfig() throws {
    let box = Sandbox("settings")
    defer { box.remove() }
    let handler = box.handler()
    handler.start()
    #expect(handler.handle(.setConfig(Config(sync: .full))) == .config(ConfigStatus(config: Config(sync: .full), path: box.file.path, onDisk: true)))
    try FileManager.default.removeItem(at: box.file.url)
    #expect(handler.handle(.updateConfig) == .config(ConfigStatus(config: Config(sync: .full), path: box.file.path, onDisk: true)))
    #expect(try box.file.load() == Config(sync: .full))
}

@MainActor @Test func updateConfigWithMalformedFileFailsAndWritesNothing() throws {
    let box = Sandbox("settings")
    defer { box.remove() }
    let handler = box.handler()
    handler.start()
    try Data("{".utf8).write(to: box.file.url)
    let response = handler.handle(.updateConfig)
    guard case let .failure(error) = response, case .configInvalid = error else {
        Issue.record("expected configInvalid, got \(String(describing: response))")
        return
    }
    #expect(handler.config == Config())
    #expect(try String(contentsOf: box.file.url, encoding: .utf8) == "{")
}

@MainActor @Test func nonConfigRequestsAreNotHandled() {
    let box = Sandbox("settings")
    defer { box.remove() }
    let handler = box.handler()
    #expect(handler.handle(.version) == nil)
    #expect(handler.handle(.readings) == nil)
    #expect(handler.handle(.shutdown) == nil)
}

@MainActor @Test func reconcileFailureReportsThatTheConfigWasSaved() throws {
    let box = Sandbox("settings")
    defer { box.remove() }
    let blocker = box.dir.appendingPathComponent("blocker")
    try Data().write(to: blocker)
    let handler = box.handler(agentURL: blocker.appendingPathComponent("a.plist"))
    handler.start()
    let response = handler.handle(.setConfig(Config(login: true, ui: true)))
    guard case let .failure(.daemonFailure(message)) = response else {
        Issue.record("expected daemonFailure, got \(String(describing: response))")
        return
    }
    #expect(message.contains("config saved to"))
    #expect(try box.file.load() == Config(login: true, ui: true))
    #expect(handler.config == Config(login: true, ui: true))
}

@MainActor @Test func onChangeFiresAfterSetAndReloadWithTheNewConfig() throws {
    let box = Sandbox("settings")
    defer { box.remove() }
    let handler = box.handler()
    var seen: [Config] = []
    handler.onChange = { seen.append($0) }
    handler.start()
    #expect(seen.isEmpty)

    let relative = Config(sync: .relative)
    _ = handler.handle(.setConfig(relative))
    #expect(seen == [relative])

    try box.file.save(Config(sync: .full))
    _ = handler.handle(.reloadConfig)
    #expect(seen == [relative, Config(sync: .full)])

    // A failed set does not fire.
    let nonBundle = box.handler(bundle: nil)
    nonBundle.onChange = { seen.append($0) }
    _ = nonBundle.handle(.setConfig(Config(login: true)))
    #expect(seen.count == 2)
}
