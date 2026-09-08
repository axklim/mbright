# Config File and Daemon Startup at Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A daemon-owned JSON config under `$XDG_CONFIG_HOME/mbright/` whose `login` and `ui` keys drive a single LaunchAgent plist, exposed through `mbright daemon enable-login|disable-login`, `mbright config show|init|reload`, and the Settings checkbox.

**Architecture:** `Config`/`ConfigStatus` are model types in `MBrightCore` that cross the wire as four new `Request` cases and one `Response` case. A new `MBrightDaemon` library holds the file I/O (`ConfigFile`), the plist (`LaunchAgent`), bundle detection (`InstalledBundle`), the pure reconcile decision (`LoginReconciler`) and the request handler that ties them together (`SettingsHandler`). `mbrightd` dispatches config requests to `SettingsHandler` before `RequestHandler`. Clients (CLI, Settings window) never touch the file or the plist.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing (`./scripts/test.sh`), ArgumentParser, AppKit. Command Line Tools only.

**Spec:** `docs/superpowers/specs/2026-09-08-config-and-login-design.md`

## Global Constraints

- Build with `swift build`; test with `./scripts/test.sh` (never bare `swift test`). Filter one test file with `./scripts/test.sh --filter <TestTargetName>`.
- Tests need no hardware and must never touch `~/Library/LaunchAgents` or `~/.config`. Use temp directories.
- Only `mbrightd` reads or writes the config file and the plist.
- Paths follow XDG. `XDG_CONFIG_HOME` is the only knob for the config path; the plist stays in `~/Library/LaunchAgents` (launchd reads nowhere else).
- Plist label: `com.axklim.mbright`. Config path: `$XDG_CONFIG_HOME/mbright/config.json`, default `~/.config/mbright/config.json`. Defaults: `login: false`, `ui: true`.
- No `KeepAlive` in the plist. Never bootstrap/bootout from code.
- No migration of the old `com.axklim.mbright.menubar` plist.
- Errors cross the wire as `MBrightError`. New cases: `loginUnavailable(reason:)`, `configInvalid(path:reason:)`.
- Keep code comments minimal; only where intent is not obvious.
- Commit after each task. Branch: `feature/config-login` (already exists, spec committed).

---

## File map

| Path | Responsibility |
| --- | --- |
| `Sources/MBrightCore/Config.swift` (new) | `Config`, `ConfigStatus` model types |
| `Sources/MBrightCore/MBrightError.swift` | two new cases + messages |
| `Sources/MBrightIPC/Messages.swift` | new `Request`/`Response` cases |
| `Sources/MBrightIPC/RequestHandler.swift` | acknowledge config cases with `.ok` |
| `Package.swift` | `MBrightDaemon` target + tests, `mbrightd` depends on it |
| `Sources/MBrightDaemon/ConfigFile.swift` (new) | XDG path, load, save |
| `Sources/MBrightDaemon/LaunchAgent.swift` (new) | plist build/read/write/remove |
| `Sources/MBrightDaemon/InstalledBundle.swift` (new) | derive app/daemon paths from the daemon's own path |
| `Sources/MBrightDaemon/LoginReconciler.swift` (new) | pure decision + apply |
| `Sources/MBrightDaemon/SettingsHandler.swift` (new) | holds `Config`, handles the four requests |
| `Sources/mbrightd/MBrightD.swift` | load settings at start, dispatch config requests |
| `Sources/mbright/ConfigCommands.swift` (new) | `enable-login`, `disable-login`, `config show|init|reload`, shared printing |
| `Sources/mbright/Commands.swift` | register subcommands, status line |
| `Sources/mbright/MBright.swift` | register `ConfigCommand` |
| `Sources/MBrightMenuBar/SettingsWindowController.swift` | talk to the daemon instead of the plist |
| `Sources/MBrightMenuBar/StatusMenuController.swift` | pass the connection to Settings |
| `Sources/MBrightMenuBar/LaunchAgent.swift` | delete |
| `Tests/MBrightCoreTests/ConfigTests.swift` (new) | |
| `Tests/MBrightIPCTests/MessageCodecTests.swift`, `RequestHandlerTests.swift` | new cases |
| `Tests/MBrightDaemonTests/*.swift` (new) | one file per unit |
| `Tests/MBrightMenuBarTests/MenuModelTests.swift` | drop the LaunchAgent tests |
| `Makefile`, `docs/architecture.md`, `docs/cli.md`, `README.md`, `CLAUDE.md` | label, docs |

---

### Task 1: `Config` and `ConfigStatus` models, new error cases

**Files:**
- Create: `Sources/MBrightCore/Config.swift`
- Modify: `Sources/MBrightCore/MBrightError.swift`
- Create: `Tests/MBrightCoreTests/ConfigTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct Config: Equatable, Sendable, Codable { public var login: Bool; public var ui: Bool; public init(login: Bool = false, ui: Bool = true) }
  public struct ConfigStatus: Equatable, Sendable, Codable { public let config: Config; public let path: String; public let onDisk: Bool; public init(config:path:onDisk:) }
  MBrightError.loginUnavailable(reason: String)
  MBrightError.configInvalid(path: String, reason: String)
  ```

- [ ] **Step 1: Write the failing tests**

`Tests/MBrightCoreTests/ConfigTests.swift`:

```swift
import Foundation
import Testing
@testable import MBrightCore

@Test func configDefaultsAreLoginOffUIOn() {
    #expect(Config() == Config(login: false, ui: true))
}

@Test func configDecodesMissingKeysAsDefaultsAndIgnoresUnknownKeys() throws {
    let decoder = JSONDecoder()
    #expect(try decoder.decode(Config.self, from: Data("{}".utf8)) == Config())
    #expect(try decoder.decode(Config.self, from: Data(#"{"login": true}"#.utf8)) == Config(login: true, ui: true))
    #expect(try decoder.decode(Config.self, from: Data(#"{"login": true, "ui": false, "future": 1}"#.utf8))
        == Config(login: true, ui: false))
}

@Test func configEncodesBothKeys() throws {
    let data = try JSONEncoder().encode(Config(login: true, ui: false))
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Bool]
    #expect(object == ["login": true, "ui": false])
}

@Test func configStatusRoundTrips() throws {
    let status = ConfigStatus(config: Config(login: true, ui: true), path: "/x/config.json", onDisk: true)
    let decoded = try JSONDecoder().decode(ConfigStatus.self, from: try JSONEncoder().encode(status))
    #expect(decoded == status)
}

@Test func newErrorsHaveMessages() {
    #expect(MBrightError.loginUnavailable(reason: "running from /tmp/mbrightd").description
        == "Launch at login needs mbright installed as an app: running from /tmp/mbrightd. Run 'make install' first.")
    #expect(MBrightError.configInvalid(path: "/x/config.json", reason: "bad json").description
        == "Could not read /x/config.json: bad json")
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/test.sh --filter MBrightCoreTests`
Expected: build error, `cannot find 'Config' in scope`.

- [ ] **Step 3: Implement**

`Sources/MBrightCore/Config.swift`:

```swift
/// User settings. Owned by the daemon; clients only see it through the
/// wire. Missing keys decode to their defaults so an older file stays
/// valid when a key is added.
public struct Config: Equatable, Sendable, Codable {
    public var login: Bool
    public var ui: Bool

    public init(login: Bool = false, ui: Bool = true) {
        self.login = login
        self.ui = ui
    }

    private enum CodingKeys: String, CodingKey { case login, ui }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        login = try container.decodeIfPresent(Bool.self, forKey: .login) ?? false
        ui = try container.decodeIfPresent(Bool.self, forKey: .ui) ?? true
    }
}

/// What the daemon reports back for every config request.
public struct ConfigStatus: Equatable, Sendable, Codable {
    public let config: Config
    public let path: String
    public let onDisk: Bool

    public init(config: Config, path: String, onDisk: Bool) {
        self.config = config
        self.path = path
        self.onDisk = onDisk
    }
}
```

In `Sources/MBrightCore/MBrightError.swift`, after `case daemonFailure(String)` add:

```swift
    /// Launch at login needs the daemon to run from the installed app
    /// bundle, so the plist has a stable program path to point at.
    case loginUnavailable(reason: String)
    /// The config file exists but could not be parsed.
    case configInvalid(path: String, reason: String)
```

and in `description`, after the `.daemonFailure` case:

```swift
        case let .loginUnavailable(reason):
            return "Launch at login needs mbright installed as an app: \(reason). Run 'make install' first."
        case let .configInvalid(path, reason):
            return "Could not read \(path): \(reason)"
```

- [ ] **Step 4: Run tests**

Run: `./scripts/test.sh --filter MBrightCoreTests`
Expected: all pass, including the 5 new tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/MBrightCore/Config.swift Sources/MBrightCore/MBrightError.swift Tests/MBrightCoreTests/ConfigTests.swift
git commit -m "feat(core): Config and ConfigStatus models, login/config error cases"
```

---

### Task 2: Wire protocol cases

**Files:**
- Modify: `Sources/MBrightIPC/Messages.swift`
- Modify: `Sources/MBrightIPC/RequestHandler.swift`
- Modify: `Tests/MBrightIPCTests/MessageCodecTests.swift`, `Tests/MBrightIPCTests/RequestHandlerTests.swift`

**Interfaces:**
- Consumes: `Config`, `ConfigStatus` from Task 1.
- Produces:
  ```swift
  Request.config, Request.setConfig(Config), Request.reloadConfig, Request.writeConfig
  Response.config(ConfigStatus)
  ```

- [ ] **Step 1: Extend the codec tests**

In `MessageCodecTests.swift`, in `clientMessagesRoundTrip` add to the array:

```swift
        ClientMessage(id: 9, request: .config),
        ClientMessage(id: 10, request: .setConfig(Config(login: true, ui: false))),
        ClientMessage(id: 11, request: .reloadConfig),
        ClientMessage(id: 12, request: .writeConfig),
```

In `serverMessagesRoundTrip` add:

```swift
        .reply(id: 9, response: .config(ConfigStatus(config: Config(login: true, ui: true), path: "/c.json", onDisk: false))),
        .reply(id: 10, response: .failure(.loginUnavailable(reason: "r"))),
        .reply(id: 11, response: .failure(.configInvalid(path: "/c.json", reason: "r"))),
```

In `RequestHandlerTests.swift`, in `versionAndSubscribeAnswerWithoutTouchingHardware` add before the `writes.isEmpty` check:

```swift
    // Config is the daemon executable's job too; the handler only acknowledges.
    #expect(handler.handle(.config) == .ok)
    #expect(handler.handle(.setConfig(Config())) == .ok)
    #expect(handler.handle(.reloadConfig) == .ok)
    #expect(handler.handle(.writeConfig) == .ok)
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/test.sh --filter MBrightIPCTests`
Expected: build error, `type 'Request' has no member 'config'`.

- [ ] **Step 3: Implement**

In `Messages.swift`, `Request`, after `case shutdown`:

```swift
    /// Config requests are handled by the daemon executable, not the
    /// request handler. All four reply with `.config(ConfigStatus)`.
    case config
    case setConfig(Config)
    case reloadConfig
    /// Creates the file from the current config if none exists.
    case writeConfig
```

In `Response`, after `case version(String)`:

```swift
    case config(ConfigStatus)
```

In `RequestHandler.handle`, change the `.subscribe, .shutdown` line to:

```swift
            case .subscribe, .shutdown, .config, .setConfig, .reloadConfig, .writeConfig:
                return .ok
```

- [ ] **Step 4: Run tests**

Run: `./scripts/test.sh --filter MBrightIPCTests`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MBrightIPC Tests/MBrightIPCTests
git commit -m "feat(ipc): config, setConfig, reloadConfig, writeConfig requests"
```

---

### Task 3: `MBrightDaemon` target and `ConfigFile`

**Files:**
- Modify: `Package.swift`
- Create: `Sources/MBrightDaemon/ConfigFile.swift`
- Create: `Tests/MBrightDaemonTests/ConfigFileTests.swift`

**Interfaces:**
- Consumes: `Config`, `MBrightError.configInvalid`, `SocketPath.xdgDirectory(_:)` (in `MBrightIPC`, returns `nil` for unset/empty/relative).
- Produces:
  ```swift
  public struct ConfigFile: Sendable {
      public static let xdgConfigVariable = "XDG_CONFIG_HOME"
      public let url: URL
      public init(url: URL)
      public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL
      public var path: String
      public var exists: Bool
      public func load() throws -> Config?      // nil when missing; throws MBrightError.configInvalid
      public func save(_ config: Config) throws
  }
  ```

- [ ] **Step 1: Add the target**

In `Package.swift` targets, after the `MBrightMenuBar` target:

```swift
        .target(name: "MBrightDaemon", dependencies: ["MBrightCore", "MBrightIPC"]),
```

Add `"MBrightDaemon"` to the `mbrightd` executable's dependencies (before the ArgumentParser product). After the `MBrightMenuBarTests` test target:

```swift
        .testTarget(name: "MBrightDaemonTests", dependencies: ["MBrightCore", "MBrightIPC", "MBrightDaemon"]),
```

- [ ] **Step 2: Write the failing tests**

`Tests/MBrightDaemonTests/ConfigFileTests.swift`:

```swift
import Foundation
import Testing
@testable import MBrightCore
@testable import MBrightDaemon

func temporaryDirectory(_ name: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mbright-\(name)-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func configPathFollowsXDGConfigHome() {
    let home = URL(fileURLWithPath: "/Users/me")
    #expect(ConfigFile.resolve(environment: ["XDG_CONFIG_HOME": "/xdg"], home: home).path == "/xdg/mbright/config.json")
    #expect(ConfigFile.resolve(environment: [:], home: home).path == "/Users/me/.config/mbright/config.json")
    #expect(ConfigFile.resolve(environment: ["XDG_CONFIG_HOME": ""], home: home).path == "/Users/me/.config/mbright/config.json")
    #expect(ConfigFile.resolve(environment: ["XDG_CONFIG_HOME": "rel"], home: home).path == "/Users/me/.config/mbright/config.json")
}

@Test func missingFileLoadsAsNil() throws {
    let dir = temporaryDirectory("config")
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = ConfigFile(url: dir.appendingPathComponent("config.json"))
    #expect(file.exists == false)
    #expect(try file.load() == nil)
}

@Test func saveCreatesDirectoryAndLoadReadsBack() throws {
    let dir = temporaryDirectory("config")
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = ConfigFile(url: dir.appendingPathComponent("nested/config.json"))
    try file.save(Config(login: true, ui: false))
    #expect(file.exists)
    #expect(try file.load() == Config(login: true, ui: false))
    let text = try String(contentsOf: file.url, encoding: .utf8)
    #expect(text.contains("\"login\" : true"))
    #expect(text.hasSuffix("\n"))
}

@Test func malformedFileIsConfigInvalid() throws {
    let dir = temporaryDirectory("config")
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = ConfigFile(url: dir.appendingPathComponent("config.json"))
    try Data("{ nope".utf8).write(to: file.url)
    #expect(throws: MBrightError.self) { try file.load() }
    do {
        _ = try file.load()
    } catch let MBrightError.configInvalid(path, _) {
        #expect(path == file.url.path)
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `./scripts/test.sh --filter MBrightDaemonTests`
Expected: build error, `cannot find 'ConfigFile'`.

- [ ] **Step 4: Implement**

`Sources/MBrightDaemon/ConfigFile.swift`:

```swift
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
            return try JSONDecoder().decode(Config.self, from: try Data(contentsOf: url))
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
```

- [ ] **Step 5: Run tests**

Run: `./scripts/test.sh --filter MBrightDaemonTests`
Expected: 4 pass. Then `swift build` to confirm every target still builds.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/MBrightDaemon Tests/MBrightDaemonTests
git commit -m "feat(daemon): MBrightDaemon target with ConfigFile"
```

---

### Task 4: `LaunchAgent` in `MBrightDaemon`

The menubar copy stays until Task 9 so the app keeps building. This one has a new label, reads plists back, and does not decide anything.

**Files:**
- Create: `Sources/MBrightDaemon/LaunchAgent.swift`
- Create: `Tests/MBrightDaemonTests/LaunchAgentTests.swift`

**Interfaces:**
- Consumes: `SocketPath.xdgDirectory`, `SocketPath.xdgRuntimeVariable`.
- Produces:
  ```swift
  public struct LaunchAgent: Equatable, Sendable {
      public static let label = "com.axklim.mbright"
      public static var defaultFileURL: URL
      public let program: String
      public let environment: [String: String]
      public init(program: String, environment: [String: String] = [:])
      public static func relevantEnvironment(_ environment: [String: String]) -> [String: String]
      public var plist: [String: Any]
      public func plistData() throws -> Data
      public static func read(at url: URL) -> LaunchAgent?   // nil: missing, unparseable, or another label
      public func write(to url: URL) throws
      public static func remove(at url: URL) throws          // no error when missing
  }
  ```

- [ ] **Step 1: Write the failing tests**

`Tests/MBrightDaemonTests/LaunchAgentTests.swift`:

```swift
import Foundation
import Testing
@testable import MBrightDaemon

@Test func launchAgentPlistPointsAtProgramWithoutKeepAlive() throws {
    let agent = LaunchAgent(program: "/Applications/mbright.app/Contents/MacOS/mbright-menubar")
    let decoded = try PropertyListSerialization.propertyList(from: agent.plistData(), format: nil) as? [String: Any]
    #expect(decoded?["Label"] as? String == "com.axklim.mbright")
    #expect(decoded?["ProgramArguments"] as? [String] == ["/Applications/mbright.app/Contents/MacOS/mbright-menubar"])
    #expect(decoded?["RunAtLoad"] as? Bool == true)
    #expect(decoded?["KeepAlive"] == nil)
    #expect(decoded?["EnvironmentVariables"] == nil)
    #expect(LaunchAgent.defaultFileURL.path.hasSuffix("/Library/LaunchAgents/com.axklim.mbright.plist"))
}

@Test func launchAgentPinsXDGRuntimeDirForLaunchd() throws {
    let agent = LaunchAgent(program: "/x/mbrightd", environment: ["XDG_RUNTIME_DIR": "/run/user/501"])
    let decoded = try PropertyListSerialization.propertyList(from: agent.plistData(), format: nil) as? [String: Any]
    #expect(decoded?["EnvironmentVariables"] as? [String: String] == ["XDG_RUNTIME_DIR": "/run/user/501"])
}

@Test func relevantEnvironmentKeepsOnlyAValidRuntimeDir() {
    #expect(LaunchAgent.relevantEnvironment(["XDG_RUNTIME_DIR": "/run/user/501", "PATH": "/bin", "HOME": "/h"])
        == ["XDG_RUNTIME_DIR": "/run/user/501"])
    #expect(LaunchAgent.relevantEnvironment(["XDG_RUNTIME_DIR": ""]).isEmpty)
    #expect(LaunchAgent.relevantEnvironment(["XDG_RUNTIME_DIR": "rel"]).isEmpty)
    #expect(LaunchAgent.relevantEnvironment([:]).isEmpty)
}

@Test func launchAgentWritesReadsBackAndRemoves() throws {
    let dir = temporaryDirectory("agent")
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("nested/a.plist")
    let agent = LaunchAgent(program: "/x/mbrightd", environment: ["XDG_RUNTIME_DIR": "/run/user/501"])

    #expect(LaunchAgent.read(at: url) == nil)
    try agent.write(to: url)
    #expect(LaunchAgent.read(at: url) == agent)
    try LaunchAgent.remove(at: url)
    #expect(LaunchAgent.read(at: url) == nil)
    // Removing twice must not throw on the missing file.
    try LaunchAgent.remove(at: url)
}

@Test func readIgnoresForeignOrBrokenPlists() throws {
    let dir = temporaryDirectory("agent")
    defer { try? FileManager.default.removeItem(at: dir) }
    let foreign = dir.appendingPathComponent("foreign.plist")
    let data = try PropertyListSerialization.data(
        fromPropertyList: ["Label": "com.other", "ProgramArguments": ["/x"]], format: .xml, options: 0)
    try data.write(to: foreign)
    #expect(LaunchAgent.read(at: foreign) == nil)

    let broken = dir.appendingPathComponent("broken.plist")
    try Data("not a plist".utf8).write(to: broken)
    #expect(LaunchAgent.read(at: broken) == nil)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/test.sh --filter MBrightDaemonTests`
Expected: build error, `cannot find 'LaunchAgent'` (the menubar one is a different module and not imported here).

- [ ] **Step 3: Implement**

`Sources/MBrightDaemon/LaunchAgent.swift`:

```swift
import Foundation
import MBrightIPC

/// The one LaunchAgent mbright writes. Only written or removed, never
/// bootstrapped: loading it while the program is already running would
/// start a second copy, and unloading would kill a copy launchd started.
/// No `KeepAlive`, so Quit or `daemon stop` ends the job until next login.
public struct LaunchAgent: Equatable, Sendable {
    public static let label = "com.axklim.mbright"

    public let program: String
    /// launchd never inherits the shell environment, so the
    /// `XDG_RUNTIME_DIR` in force is pinned here or the login-started
    /// process would resolve a different socket than the CLI.
    public let environment: [String: String]

    public init(program: String, environment: [String: String] = [:]) {
        self.program = program
        self.environment = environment
    }

    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    /// The subset of `environment` that changes where mbright puts files.
    public static func relevantEnvironment(_ environment: [String: String]) -> [String: String] {
        guard let runtime = SocketPath.xdgDirectory(environment[SocketPath.xdgRuntimeVariable]) else { return [:] }
        return [SocketPath.xdgRuntimeVariable: runtime]
    }

    public var plist: [String: Any] {
        var plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [program],
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

    /// `nil` for a missing file, an unparseable one, or one with another
    /// label; those are not ours to reason about.
    public static func read(at url: URL) -> LaunchAgent? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["Label"] as? String == label,
              let program = (plist["ProgramArguments"] as? [String])?.first
        else { return nil }
        return LaunchAgent(program: program, environment: plist["EnvironmentVariables"] as? [String: String] ?? [:])
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plistData().write(to: url, options: .atomic)
    }

    public static func remove(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `./scripts/test.sh --filter MBrightDaemonTests`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MBrightDaemon/LaunchAgent.swift Tests/MBrightDaemonTests/LaunchAgentTests.swift
git commit -m "feat(daemon): LaunchAgent with the com.axklim.mbright label"
```

---

### Task 5: `InstalledBundle` and `LoginReconciler`

**Files:**
- Create: `Sources/MBrightDaemon/InstalledBundle.swift`
- Create: `Sources/MBrightDaemon/LoginReconciler.swift`
- Create: `Tests/MBrightDaemonTests/InstalledBundleTests.swift`, `Tests/MBrightDaemonTests/LoginReconcilerTests.swift`

**Interfaces:**
- Consumes: `LaunchAgent` (Task 4), `Config` (Task 1).
- Produces:
  ```swift
  public struct InstalledBundle: Equatable, Sendable {
      public let root: URL                       // .../mbright.app
      public init?(daemonExecutable: String)    // nil unless <x>.app/Contents/Helpers/mbrightd
      public var daemon: String                  // root/Contents/Helpers/mbrightd
      public var app: String                     // root/Contents/MacOS/mbright-menubar
      public func program(for config: Config) -> String   // ui ? app : daemon
  }
  public enum LoginReconciler {
      public enum Trigger: Sendable { case start, explicit }
      public enum Action: Equatable, Sendable { case write(LaunchAgent), remove, leave }
      public static func action(config: Config, bundle: InstalledBundle?, environment: [String: String], existing: LaunchAgent?, trigger: Trigger) -> Action
      public static func apply(_ action: Action, at url: URL) throws
  }
  ```

- [ ] **Step 1: Write the failing tests**

`Tests/MBrightDaemonTests/InstalledBundleTests.swift`:

```swift
import Testing
@testable import MBrightCore
@testable import MBrightDaemon

@Test func bundleIsDerivedFromTheHelpersPath() {
    let bundle = InstalledBundle(daemonExecutable: "/Users/me/Applications/mbright.app/Contents/Helpers/mbrightd")
    #expect(bundle?.root.path == "/Users/me/Applications/mbright.app")
    #expect(bundle?.daemon == "/Users/me/Applications/mbright.app/Contents/Helpers/mbrightd")
    #expect(bundle?.app == "/Users/me/Applications/mbright.app/Contents/MacOS/mbright-menubar")
    #expect(bundle?.program(for: Config(login: true, ui: true)) == bundle?.app)
    #expect(bundle?.program(for: Config(login: true, ui: false)) == bundle?.daemon)
}

@Test func anythingOutsideABundleIsNotInstalled() {
    #expect(InstalledBundle(daemonExecutable: "/Users/me/.cache/mbright/build/debug/mbrightd") == nil)
    #expect(InstalledBundle(daemonExecutable: "/Users/me/Applications/mbright.app/Contents/MacOS/mbrightd") == nil)
    #expect(InstalledBundle(daemonExecutable: "/Users/me/Applications/mbright.app/Contents/Helpers/other") == nil)
    #expect(InstalledBundle(daemonExecutable: "/opt/mbright/Contents/Helpers/mbrightd") == nil)
}
```

`Tests/MBrightDaemonTests/LoginReconcilerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/test.sh --filter MBrightDaemonTests`
Expected: build error, `cannot find 'InstalledBundle'`.

- [ ] **Step 3: Implement**

`Sources/MBrightDaemon/InstalledBundle.swift`:

```swift
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
```

`Sources/MBrightDaemon/LoginReconciler.swift`:

```swift
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
```

- [ ] **Step 4: Run tests**

Run: `./scripts/test.sh --filter MBrightDaemonTests`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MBrightDaemon/InstalledBundle.swift Sources/MBrightDaemon/LoginReconciler.swift Tests/MBrightDaemonTests/InstalledBundleTests.swift Tests/MBrightDaemonTests/LoginReconcilerTests.swift
git commit -m "feat(daemon): InstalledBundle detection and LoginReconciler"
```

---

### Task 6: `SettingsHandler`

**Files:**
- Create: `Sources/MBrightDaemon/SettingsHandler.swift`
- Create: `Tests/MBrightDaemonTests/SettingsHandlerTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1 to 5.
- Produces:
  ```swift
  @MainActor public final class SettingsHandler {
      public private(set) var config: Config
      public init(file: ConfigFile, agentURL: URL, bundle: InstalledBundle?, environment: [String: String], log: @escaping (String) -> Void)
      public func start()                       // load (defaults on missing/malformed, logs malformed), reconcile .start
      public var status: ConfigStatus
      public func handle(_ request: Request) -> Response?   // nil for non-config requests
  }
  ```
  `LineServer.Handler` is `@Sendable`, so the handler is `@MainActor` (implicitly `Sendable`) and the daemon calls it through `MainActor.assumeIsolated`, the same way the rest of `MBrightD.run()` works. Tests are `@MainActor`.

- [ ] **Step 1: Write the failing tests**

`Tests/MBrightDaemonTests/SettingsHandlerTests.swift`:

```swift
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

    func handler(bundle: InstalledBundle? = bundle, environment: [String: String] = [:],
                 log: @escaping (String) -> Void = { _ in }) -> SettingsHandler {
        SettingsHandler(file: file, agentURL: agentURL, bundle: bundle, environment: environment, log: log)
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

@MainActor @Test func nonConfigRequestsAreNotHandled() {
    let box = Sandbox("settings")
    defer { box.remove() }
    let handler = box.handler()
    #expect(handler.handle(.version) == nil)
    #expect(handler.handle(.readings) == nil)
    #expect(handler.handle(.shutdown) == nil)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./scripts/test.sh --filter MBrightDaemonTests`
Expected: build error, `cannot find 'SettingsHandler'`.

- [ ] **Step 3: Implement**

`Sources/MBrightDaemon/SettingsHandler.swift`:

```swift
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
```

- [ ] **Step 4: Run tests**

Run: `./scripts/test.sh --filter MBrightDaemonTests`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MBrightDaemon/SettingsHandler.swift Tests/MBrightDaemonTests/SettingsHandlerTests.swift
git commit -m "feat(daemon): SettingsHandler owns the config and the login plist"
```

---

### Task 7: Wire `SettingsHandler` into `mbrightd`

**Files:**
- Modify: `Sources/mbrightd/MBrightD.swift`

**Interfaces:**
- Consumes: `SettingsHandler`, `ConfigFile.resolve()`, `LaunchAgent.defaultFileURL`, `InstalledBundle(daemonExecutable:)`.

No unit test: this is the executable's composition root, covered by the hardware check in Task 11.

- [ ] **Step 1: Implement**

In `MBrightD.swift` add `import MBrightDaemon`. In `run()`, after the `let handler = RequestHandler(controller: controller)` line, add:

```swift
        let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
        let settings = SettingsHandler(
            file: ConfigFile(url: ConfigFile.resolve()),
            agentURL: LaunchAgent.defaultFileURL,
            bundle: InstalledBundle(daemonExecutable: executable),
            environment: ProcessInfo.processInfo.environment,
            log: { FileHandle.standardError.write(Data("\($0)\n".utf8)) })
        settings.start()
```

In the `LineServer` handler closure, before `return handler.handle(request)`:

```swift
                if let response = MainActor.assumeIsolated({ settings.handle(request) }) { return response }
```

Update the `discussion` string to mention the config:

```swift
        discussion: """
            Listens on $XDG_RUNTIME_DIR/mbright/mbrightd.sock, or the per-user temp dir \
            when XDG_RUNTIME_DIR is unset. Reads $XDG_CONFIG_HOME/mbright/config.json and \
            keeps the login LaunchAgent in step with it. Runs in the foreground until \
            SIGTERM or 'mbright daemon stop'.
            """,
```

- [ ] **Step 2: Build and run the full suite**

Run: `swift build && ./scripts/test.sh`
Expected: builds, all tests pass.

- [ ] **Step 3: Smoke test with scratch XDG dirs (no hardware assertions)**

```bash
mkdir -p /tmp/cfgtest/rt /tmp/cfgtest/cfg
XDG_RUNTIME_DIR=/tmp/cfgtest/rt XDG_CONFIG_HOME=/tmp/cfgtest/cfg .build/debug/mbrightd &
sleep 1
XDG_RUNTIME_DIR=/tmp/cfgtest/rt .build/debug/mbright daemon status
pkill -TERM -f '.build/debug/mbrightd'
```

Expected: `mbrightd <version> is running on /tmp/cfgtest/rt/mbright/mbrightd.sock`, no warning on stderr, nothing written under `/tmp/cfgtest/cfg`, `~/Library/LaunchAgents/com.axklim.mbright.plist` absent.

- [ ] **Step 4: Commit**

```bash
git add Sources/mbrightd/MBrightD.swift
git commit -m "feat(mbrightd): load the config at start and serve config requests"
```

---

### Task 8: CLI commands

**Files:**
- Create: `Sources/mbright/ConfigCommands.swift`
- Modify: `Sources/mbright/Commands.swift` (`DaemonCommand` subcommands, `DaemonStatus`)
- Modify: `Sources/mbright/MBright.swift`

**Interfaces:**
- Consumes: `perform(_:autostart:)`, `unexpected(_:)`, `DaemonOptions` from `TargetOptions.swift`; `Request`/`Response` config cases.
- Produces: `mbright daemon enable-login [--no-ui]`, `mbright daemon disable-login`, `mbright config show|init|reload`, and the login line in `mbright daemon status`.

There are no CLI unit tests in this repo (ArgumentParser commands are exercised by hand). Verify by running the binary.

- [ ] **Step 1: Implement the shared printing and the commands**

`Sources/mbright/ConfigCommands.swift`:

```swift
import ArgumentParser
import Foundation
import MBrightCore
import MBrightIPC

func loginLine(_ config: Config) -> String {
    guard config.login else { return "login: disabled" }
    return "login: enabled, starts \(config.ui ? "the menu bar app" : "mbrightd only")"
}

func describe(_ status: ConfigStatus) -> String {
    let path = (status.path as NSString).abbreviatingWithTildeInPath
    return """
        \(path)\(status.onDisk ? "" : " (not written yet)")
        \(loginLine(status.config))
        ui: \(status.config.ui ? "menu bar app" : "mbrightd only")
        """
}

func configStatus(_ request: Request, autostart: Bool) throws -> ConfigStatus {
    let response = try perform(request, autostart: autostart)
    guard case let .config(status) = response else { throw unexpected(response) }
    return status
}

struct DaemonEnableLogin: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enable-login",
        abstract: "Start mbright at login. Takes effect at the next login."
    )

    @Flag(name: .customLong("no-ui"), help: "Start mbrightd alone instead of the menu bar app.")
    var noUI = false

    @OptionGroup var daemon: DaemonOptions

    func run() throws {
        let status = try configStatus(.setConfig(Config(login: true, ui: !noUI)), autostart: daemon.daemonAutostart)
        print(loginLine(status.config))
    }
}

struct DaemonDisableLogin: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable-login",
        abstract: "Stop starting mbright at login."
    )

    @OptionGroup var daemon: DaemonOptions

    func run() throws {
        // Read first so the ui key survives; only login changes here.
        var config = try configStatus(.config, autostart: daemon.daemonAutostart).config
        config.login = false
        let status = try configStatus(.setConfig(config), autostart: daemon.daemonAutostart)
        print(loginLine(status.config))
    }
}

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Show, create, or reload the config file.",
        subcommands: [ConfigShow.self, ConfigInit.self, ConfigReload.self],
        defaultSubcommand: ConfigShow.self
    )
}

struct ConfigShow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Print the config path and the settings mbrightd holds."
    )

    @OptionGroup var daemon: DaemonOptions

    func run() throws {
        print(describe(try configStatus(.config, autostart: daemon.daemonAutostart)))
    }
}

struct ConfigInit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Write the config file from the current settings, if it does not exist."
    )

    @OptionGroup var daemon: DaemonOptions

    func run() throws {
        let before = try configStatus(.config, autostart: daemon.daemonAutostart)
        let path = (before.path as NSString).abbreviatingWithTildeInPath
        guard !before.onDisk else {
            print("\(path) already exists")
            return
        }
        _ = try configStatus(.writeConfig, autostart: daemon.daemonAutostart)
        print("wrote \(path)")
    }
}

struct ConfigReload: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reload",
        abstract: "Re-read the config file and update the login LaunchAgent."
    )

    @OptionGroup var daemon: DaemonOptions

    func run() throws {
        print(describe(try configStatus(.reloadConfig, autostart: daemon.daemonAutostart)))
    }
}
```

In `Commands.swift`, `DaemonCommand.configuration`:

```swift
        subcommands: [DaemonStart.self, DaemonStop.self, DaemonStatus.self, DaemonEnableLogin.self, DaemonDisableLogin.self]
```

In `DaemonStatus.run()`, after `print("mbrightd \(version) is running on \(path)")`:

```swift
            print(loginLine(try configStatus(.config, autostart: false).config))
```

In `MBright.swift` add `ConfigCommand.self,` after `DaemonCommand.self,`.

- [ ] **Step 2: Build and verify by hand against a scratch daemon**

```bash
swift build
mkdir -p /tmp/cfgtest/rt /tmp/cfgtest/cfg
export XDG_RUNTIME_DIR=/tmp/cfgtest/rt XDG_CONFIG_HOME=/tmp/cfgtest/cfg
.build/debug/mbrightd &
sleep 1
.build/debug/mbright config show
.build/debug/mbright daemon status
.build/debug/mbright config init
.build/debug/mbright config init
.build/debug/mbright daemon enable-login; echo "exit=$?"
.build/debug/mbright daemon disable-login
printf '{"login": false, "ui": false}\n' > /tmp/cfgtest/cfg/mbright/config.json
.build/debug/mbright config reload
printf '{' > /tmp/cfgtest/cfg/mbright/config.json
.build/debug/mbright config reload; echo "exit=$?"
.build/debug/mbright daemon stop
unset XDG_RUNTIME_DIR XDG_CONFIG_HOME
```

Expected, in order:
- `show`: `/tmp/cfgtest/cfg/mbright/config.json (not written yet)`, `login: disabled`, `ui: menu bar app`.
- `status`: running line, then `login: disabled`.
- first `init`: `wrote /tmp/cfgtest/cfg/mbright/config.json`; second: `... already exists`.
- `enable-login` from the build directory: `Error: Launch at login needs mbright installed as an app: mbrightd is running from .../.build/debug/mbrightd. Run 'make install' first.` with exit 1.
- `disable-login`: `login: disabled`.
- `reload` after the edit: `ui: mbrightd only`.
- `reload` on `{`: `Error: Could not read /tmp/cfgtest/cfg/mbright/config.json: ...`, exit 1.
- `~/Library/LaunchAgents/com.axklim.mbright.plist` never appeared.

- [ ] **Step 3: Run the suite and commit**

```bash
./scripts/test.sh
git add Sources/mbright
git commit -m "feat(cli): daemon enable-login/disable-login and config show/init/reload"
```

---

### Task 9: Settings window talks to the daemon; drop the menubar `LaunchAgent`

**Files:**
- Modify: `Sources/MBrightMenuBar/SettingsWindowController.swift`
- Modify: `Sources/MBrightMenuBar/StatusMenuController.swift:27` (`self.settings = SettingsWindowController()`)
- Delete: `Sources/MBrightMenuBar/LaunchAgent.swift`
- Modify: `Tests/MBrightMenuBarTests/MenuModelTests.swift` (remove the four `launchAgent*`/`relevantEnvironment*` tests and the `import Foundation` if it becomes unused)

**Interfaces:**
- Consumes: `DaemonConnection.send(_:completion:)`, `Request.config`, `Request.setConfig`, `Response.config`, `Response.failure`.

- [ ] **Step 1: Remove the old tests**

In `Tests/MBrightMenuBarTests/MenuModelTests.swift` delete `launchAgentPlistPointsAtExecutable`, `launchAgentPinsXDGRuntimeDirForLaunchd`, `relevantEnvironmentKeepsOnlyAValidRuntimeDir`, `launchAgentWritesAndRemovesItsFile`. Delete `Sources/MBrightMenuBar/LaunchAgent.swift`.

Run: `swift build`
Expected: fails in `SettingsWindowController.swift`, `cannot find 'LaunchAgent'`.

- [ ] **Step 2: Rewrite `SettingsWindowController`**

Replace the file with:

```swift
import AppKit
import Foundation
import MBrightCore
import MBrightIPC

/// A single-pane settings window. The one setting is Launch at login,
/// which lives in the daemon's config; this window only sends requests
/// and shows what comes back.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    private let launchAtLogin = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let connection: DaemonConnection
    private var current = Config()

    init(connection: DaemonConnection) {
        self.connection = connection

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 130),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "mbright Settings"
        window.isReleasedWhenClosed = false

        launchAtLogin.target = self
        launchAtLogin.action = #selector(toggleLaunchAtLogin)

        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor

        let version = NSTextField(labelWithString: "mbright \(Version.current)")
        version.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        version.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [launchAtLogin, status, version])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
    }

    func show() {
        launchAtLogin.isEnabled = false
        status.stringValue = "Takes effect at the next login."
        connection.send(.config) { [weak self] response in
            self?.apply(response)
        }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        launchAtLogin.isEnabled = false
        let wanted = launchAtLogin.state == .on
        connection.send(.setConfig(Config(login: wanted, ui: true))) { [weak self] response in
            self?.apply(response)
        }
    }

    /// The checkbox always shows what the daemon holds, so a failed change
    /// snaps it back.
    private func apply(_ response: Response) {
        launchAtLogin.isEnabled = true
        switch response {
        case let .config(configStatus):
            current = configStatus.config
            status.stringValue = "Takes effect at the next login."
        case let .failure(error):
            status.stringValue = "\(error)"
        default:
            status.stringValue = "Unexpected reply from mbrightd."
        }
        launchAtLogin.state = current.login ? .on : .off
    }
}
```

In `StatusMenuController.init`, change `self.settings = SettingsWindowController()` to `self.settings = SettingsWindowController(connection: connection)`.

- [ ] **Step 3: Build, test, run the app**

```bash
swift build && ./scripts/test.sh
make run
```

In the app: open Settings. Expected: checkbox unchecked, text "Takes effect at the next login." Tick it. Expected with a debug build: the checkbox snaps back to unchecked and the label shows `Launch at login needs mbright installed as an app: ... Run 'make install' first.` Quit the app (Ctrl-C in the terminal also works).

- [ ] **Step 4: Commit**

```bash
git add -A Sources/MBrightMenuBar Tests/MBrightMenuBarTests
git commit -m "feat(menubar): Launch at login checkbox goes through the daemon's config"
```

---

### Task 10: Makefile, docs, CLAUDE.md

**Files:**
- Modify: `Makefile:49-51` (label), `docs/architecture.md`, `docs/cli.md`, `README.md`, `CLAUDE.md`

- [ ] **Step 1: Makefile**

Replace lines 49 to 51 with:

```make
# Written by mbrightd from the config's login key; launchd reads only this path.
LAUNCH_AGENT_LABEL := com.axklim.mbright
LAUNCH_AGENT       := $(HOME)/Library/LaunchAgents/$(LAUNCH_AGENT_LABEL).plist
```

Update the `uninstall` comment: replace "the app never bootstraps it, so it is only loaded if this login started the app" with "mbrightd never bootstraps it, so it is only loaded if this login started mbright".

- [ ] **Step 2: `docs/architecture.md`**

Replace the last two sentences of the `mbright-menubar` paragraph (from "That rules out `SMAppService`") with:

```
That rules out `SMAppService`, so Launch at login is a LaunchAgent plist
in `~/Library/LaunchAgents`, written by the daemon from its config.
```

Add to the `mbrightd` paragraph, after "unlinking the socket on the way out.":

```
It owns the config file: it reads `$XDG_CONFIG_HOME/mbright/config.json`
at start (defaults when missing, a stderr warning when malformed) and is
the only process that writes it. The `login` and `ui` keys drive one
LaunchAgent plist, `com.axklim.mbright`, that starts either the menu bar
app (which starts the daemon, as always) or `mbrightd` alone. The daemon
reconciles the plist with the config at start, on `reloadConfig`, and on
every `setConfig`; it never bootstraps it, and the plist has no
`KeepAlive`, so Quit or `daemon stop` ends a login-started daemon until
the next login. A daemon outside `mbright.app/Contents/Helpers` (a
`make run` debug build) skips reconcile and refuses to enable login,
so a scratch daemon never rewrites the real plist.
```

Libraries table: add a row `| `MBrightDaemon` | Config file, LaunchAgent plist, bundle detection, login reconcile, `SettingsHandler` |` and change the `MBrightMenuBar` row to end with `Settings window`.

Wire protocol block: add `| config | setConfig(config) | reloadConfig | writeConfig` to `Request` and `| config(ConfigStatus)` to `Response`.

Files table: replace the `Config (planned, #6)` row with `| Config | `$XDG_CONFIG_HOME/mbright/config.json` (`{"login": false, "ui": true}` by default; only mbrightd writes it) |` and the LaunchAgent row's path with `com.axklim.mbright.plist`.

Replace the last paragraph ("launchd does not inherit the shell environment...") with:

```
launchd does not inherit the shell environment, so `enable-login` pins
the `XDG_RUNTIME_DIR` in force into the plist's `EnvironmentVariables`.
At start and on reload the daemon keeps whatever the plist already
pins, so a daemon started from a terminal with a scratch runtime dir
does not move the login socket.

Upgrading from a version whose Settings wrote
`~/Library/LaunchAgents/com.axklim.mbright.menubar.plist`: remove that
file by hand and run `mbright daemon enable-login`. Nothing migrates it.
```

- [ ] **Step 3: `docs/cli.md`**

In the usage block add after the `daemon` line:

```
mbright daemon enable-login [--no-ui]   start at login; --no-ui starts mbrightd alone
mbright daemon disable-login
mbright config [show]                   config path and current settings
mbright config init                     write the file from current settings
mbright config reload                   re-read a hand-edited file
```

Add a section before "## Menu bar app":

```
## daemon status, login and config

`daemon status` prints the running line and then the login state:

```
mbrightd 0.4.0 is running on /var/folders/.../mbright/mbrightd.sock
login: enabled, starts the menu bar app
```

`enable-login` and `disable-login` print the resulting login line. Both
need the installed app (`make install`); from a build-directory daemon
`enable-login` fails naming the path it runs from. Takes effect at the next
login.

`config show` prints the path, whether the file exists, and the values:

```
~/.config/mbright/config.json (not written yet)
login: disabled
ui: menu bar app
```

`config init` writes that file once and never overwrites it. `config
reload` re-reads it after a hand edit and prints the same block; a
malformed file is an error and the daemon keeps its previous settings.
Only `mbrightd` touches the file, so every config command needs a running
daemon or `--daemon-autostart`.
```

In "## Menu bar app", replace "Settings has one option, Launch at login, which writes a LaunchAgent plist and takes effect at the next login." with "Settings has one option, Launch at login, the same setting as `mbright daemon enable-login`; it takes effect at the next login."

- [ ] **Step 4: `README.md`**

After `mbright daemon stop` in the usage block add:

```
mbright daemon enable-login   # start at login (also in the app's Settings)
```

- [ ] **Step 5: `CLAUDE.md`**

In "Verifying on hardware", after "and `pkill -TERM -f mbrightd` afterwards." add: "Add a scratch `XDG_CONFIG_HOME` too. A scratch daemon never rewrites the login plist, and a build-directory daemon cannot enable login; only the installed bundle can."

- [ ] **Step 6: Build, test, commit**

```bash
swift build && ./scripts/test.sh
git add Makefile docs/architecture.md docs/cli.md README.md CLAUDE.md
git commit -m "docs: config file, login commands, new LaunchAgent label"
```

---

### Task 11: Verify on the installed bundle

The reconcile guard and the plist only work from `~/Applications/mbright.app`. Check the real path once, then leave the machine as it was.

- [ ] **Step 1: Install and check the real plist flow**

```bash
make install
sleep 2
mbright daemon status
mbright daemon enable-login
cat ~/Library/LaunchAgents/com.axklim.mbright.plist
mbright daemon enable-login --no-ui
grep -A1 ProgramArguments -m1 ~/Library/LaunchAgents/com.axklim.mbright.plist
mbright config show
mbright daemon disable-login
ls ~/Library/LaunchAgents/com.axklim.mbright.plist
```

Expected: `status` shows `login: disabled`; after `enable-login` the plist exists with `Label` `com.axklim.mbright`, `ProgramArguments` = `~/Applications/mbright.app/Contents/MacOS/mbright-menubar`, `RunAtLoad`, no `KeepAlive`, no `EnvironmentVariables` (shell has no `XDG_RUNTIME_DIR`); `--no-ui` switches the program to `Contents/Helpers/mbrightd`; `show` prints `~/.config/mbright/config.json` and `ui: mbrightd only`; `disable-login` removes the plist (`ls` fails).

- [ ] **Step 2: Scratch daemon does not touch the real plist**

```bash
mbright daemon enable-login
mkdir -p /tmp/cfgtest/rt
XDG_RUNTIME_DIR=/tmp/cfgtest/rt ~/Applications/mbright.app/Contents/Helpers/mbrightd &
sleep 1
grep -c EnvironmentVariables ~/Library/LaunchAgents/com.axklim.mbright.plist
pkill -TERM -f '/tmp/cfgtest' ; XDG_RUNTIME_DIR=/tmp/cfgtest/rt mbright daemon stop
mbright daemon disable-login
```

Expected: `grep -c` prints `0`. The scratch daemon left the real plist alone.

- [ ] **Step 3: Settings window on the installed app**

Open Settings from the menu bar app, tick Launch at login. Expected: checkbox stays ticked, plist appears. Untick. Expected: plist gone. Run `mbright config show` and confirm `login: disabled`.

- [ ] **Step 4: Restore**

Leave login disabled unless you want it, confirm `ls ~/Library/LaunchAgents/` shows no `com.axklim.mbright.plist`, and delete `/tmp/cfgtest`. No commit; nothing changed in the repo.
