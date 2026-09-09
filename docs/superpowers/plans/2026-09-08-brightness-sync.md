# Brightness Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the main display's brightness changes, `mbrightd` moves the other displays too, in full (same value) or relative (same delta) mode, switchable from the config, the CLI, and the Settings window.

**Architecture:** A `SyncMode` joins `Config`. A new main-actor `BrightnessSync` in `MBrightDaemon` handles `set`/`adjust` requests ahead of `RequestHandler`, propagates its own writes to main in the request, and reacts to external main changes through the existing brightness change notification. It tracks main's last known percent; an equal notification value is its own write and is ignored. No new wire types: the mode rides in `setConfig`.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing (`./scripts/test.sh`, never bare `swift test`), AppKit, swift-argument-parser.

**Spec:** `docs/superpowers/specs/2026-09-08-brightness-sync-design.md`

## Global Constraints

- Build with Command Line Tools only; no Xcode, no `SMAppService`.
- Only `mbrightd` touches displays. Clients use the typed `MBrightIPC` protocol.
- Tests need no hardware: run against `FakeEnumerator` / `FakeBackend`.
- Errors cross the wire as `MBrightError`; CLI messages and exit codes stay as they were in-process.
- No per-display exclude (that is issue #13). No per-display offset. No smooth transitions.
- Comments only where intent is not obvious. Conventional Commits, one commit per task, never amend a pushed commit.
- Run `./scripts/test.sh` before every commit.

---

### Task 1: `SyncMode` and `Config.sync`

**Files:**
- Modify: `Sources/MBrightCore/Config.swift`
- Test: `Tests/MBrightCoreTests/ConfigTests.swift`

**Interfaces:**
- Produces: `public enum SyncMode: String, CaseIterable, Codable, Sendable { case off, full, relative }` and `Config.sync: SyncMode` (default `.off`), with `Config.init(login: Bool = false, ui: Bool = true, sync: SyncMode = .off)`.

- [ ] **Step 1: Write the failing tests**

Replace `configDefaultsAreLoginOffUIOn`, `configDecodesMissingKeysAsDefaultsAndIgnoresUnknownKeys`, and `configEncodesBothKeys` in `Tests/MBrightCoreTests/ConfigTests.swift` with:

```swift
@Test func configDefaultsAreLoginOffUIOnSyncOff() {
    #expect(Config() == Config(login: false, ui: true, sync: .off))
}

@Test func configDecodesMissingKeysAsDefaultsAndIgnoresUnknownKeys() throws {
    let decoder = JSONDecoder()
    #expect(try decoder.decode(Config.self, from: Data("{}".utf8)) == Config())
    #expect(try decoder.decode(Config.self, from: Data(#"{"login": true}"#.utf8)) == Config(login: true, ui: true))
    #expect(try decoder.decode(Config.self, from: Data(#"{"login": true, "ui": false, "future": 1}"#.utf8))
        == Config(login: true, ui: false))
}

@Test func configDecodesEverySyncModeAndRejectsUnknownOnes() throws {
    let decoder = JSONDecoder()
    for mode in SyncMode.allCases {
        let json = #"{"sync": "\#(mode.rawValue)"}"#
        #expect(try decoder.decode(Config.self, from: Data(json.utf8)) == Config(sync: mode))
    }
    #expect(throws: DecodingError.self) {
        try decoder.decode(Config.self, from: Data(#"{"sync": "sideways"}"#.utf8))
    }
}

@Test func configEncodesEveryKey() throws {
    let data = try JSONEncoder().encode(Config(login: true, ui: false, sync: .relative))
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(object?["login"] as? Bool == true)
    #expect(object?["ui"] as? Bool == false)
    #expect(object?["sync"] as? String == "relative")
    #expect(object?.count == 3)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./scripts/test.sh --filter MBrightCoreTests.config`
Expected: compile error, `SyncMode` and `sync:` not found.

- [ ] **Step 3: Add `SyncMode` and the `sync` key**

Replace the `Config` struct in `Sources/MBrightCore/Config.swift` with:

```swift
/// How the other displays follow the main display.
public enum SyncMode: String, CaseIterable, Equatable, Sendable, Codable {
    case off
    /// Other displays are set to the main display's value.
    case full
    /// Other displays move by the same delta as the main display.
    case relative
}

/// User settings. Owned by the daemon; clients only see it through the
/// wire. Missing keys decode to their defaults so an older file stays
/// valid when a key is added.
public struct Config: Equatable, Sendable, Codable {
    public var login: Bool
    public var ui: Bool
    public var sync: SyncMode

    public init(login: Bool = false, ui: Bool = true, sync: SyncMode = .off) {
        self.login = login
        self.ui = ui
        self.sync = sync
    }

    private enum CodingKeys: String, CodingKey { case login, ui, sync }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        login = try container.decodeIfPresent(Bool.self, forKey: .login) ?? false
        ui = try container.decodeIfPresent(Bool.self, forKey: .ui) ?? true
        sync = try container.decodeIfPresent(SyncMode.self, forKey: .sync) ?? .off
    }
}
```

Leave `ConfigStatus` as it is.

- [ ] **Step 4: Run the whole suite**

Run: `./scripts/test.sh`
Expected: all pass. `Tests/MBrightDaemonTests/SettingsHandlerTests.swift` and `Tests/MBrightIPCTests/MessageCodecTests.swift` build `Config(login:ui:)`, which still compiles because `sync` has a default.

- [ ] **Step 5: Commit**

```bash
git add Sources/MBrightCore/Config.swift Tests/MBrightCoreTests/ConfigTests.swift
git commit -m "feat(config): add sync mode key (off, full, relative)"
```

---

### Task 2: `BrightnessSync` engine

**Files:**
- Modify: `Sources/MBrightCore/BrightnessController.swift:56` (make `resolve` public)
- Create: `Sources/MBrightDaemon/BrightnessSync.swift`
- Create: `Tests/MBrightDaemonTests/Fakes.swift`
- Test: `Tests/MBrightDaemonTests/BrightnessSyncTests.swift`

**Interfaces:**
- Consumes: `SyncMode` from Task 1; `BrightnessController.set/adjust/get/readings`; `Request`, `Response`, `Target`, `MBrightError` from `MBrightIPC`/`MBrightCore`.
- Produces:
  ```swift
  @MainActor public final class BrightnessSync {
      public init(controller: BrightnessController, log: @escaping (String) -> Void)
      public private(set) var mode: SyncMode
      public var lastMain: Int? { get }
      public func setMode(_ new: SyncMode)
      public func displaysChanged()
      public func brightnessChanged(id: CGDirectDisplayID, percent: Int)
      public func handle(_ request: Request) -> Response?   // .set / .adjust only, nil otherwise
  }
  ```

- [ ] **Step 1: Make `BrightnessController.resolve` public**

In `Sources/MBrightCore/BrightnessController.swift`, change

```swift
    func resolve(_ target: Target) throws -> [DisplayInfo] {
```

to

```swift
    /// The displays a target names, in list order. Public so the daemon's
    /// sync can tell which displays a request wrote.
    public func resolve(_ target: Target) throws -> [DisplayInfo] {
```

- [ ] **Step 2: Add fakes to the daemon test target**

Create `Tests/MBrightDaemonTests/Fakes.swift` (the core and IPC test targets each carry their own copy; this follows that pattern):

```swift
import CoreGraphics
@testable import MBrightCore

let studio = DisplayInfo(index: 0, id: 3, name: "Studio Display", vendor: "APP", isMain: true)
let ultrafine = DisplayInfo(index: 1, id: 2, name: "LG UltraFine", vendor: "GSM", isMain: false)

final class FakeEnumerator: DisplayEnumerating, @unchecked Sendable {
    var displays: [DisplayInfo]
    init(_ displays: [DisplayInfo] = [studio, ultrafine]) { self.displays = displays }
    func onlineDisplays() throws -> [DisplayInfo] { displays }
}

final class FakeBackend: BrightnessBackend, @unchecked Sendable {
    var values: [CGDirectDisplayID: Float]
    /// IDs that report brightness control as unavailable.
    var unsupported: Set<CGDirectDisplayID> = []
    /// IDs whose set/get calls throw.
    var failing: Set<CGDirectDisplayID> = []
    private(set) var writes: [(id: CGDirectDisplayID, value: Float)] = []

    init(values: [CGDirectDisplayID: Float] = [3: 0.5, 2: 0.5]) { self.values = values }

    func canChangeBrightness(_ id: CGDirectDisplayID) -> Bool { !unsupported.contains(id) }

    func getBrightness(_ id: CGDirectDisplayID) throws -> Float {
        if failing.contains(id) { throw MBrightError.operationFailed(displayID: id, code: -1) }
        return values[id] ?? 0
    }

    func setBrightness(_ id: CGDirectDisplayID, _ value: Float) throws {
        if failing.contains(id) { throw MBrightError.operationFailed(displayID: id, code: -1) }
        values[id] = value
        writes.append((id, value))
    }

    /// Current value of one display as a percent, for assertions.
    func percent(_ id: CGDirectDisplayID) -> Int { Percent.fromDevice(values[id] ?? 0) }
}
```

- [ ] **Step 3: Write the failing tests**

Create `Tests/MBrightDaemonTests/BrightnessSyncTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import MBrightCore
@testable import MBrightDaemon
@testable import MBrightIPC

private final class Lines: @unchecked Sendable { var value: [String] = [] }

/// Fakes plus a sync already switched to `mode`. Note that `.full` snaps
/// at construction, so tests counting writes clear `backend.writes` first.
@MainActor
private struct Rig {
    let enumerator: FakeEnumerator
    let backend: FakeBackend
    let sync: BrightnessSync
    private let lines: Lines
    var logged: [String] { lines.value }

    init(values: [CGDirectDisplayID: Float] = [3: 0.5, 2: 0.3], mode: SyncMode = .off,
         displays: [DisplayInfo] = [studio, ultrafine]) {
        let enumerator = FakeEnumerator(displays)
        let backend = FakeBackend(values: values)
        let lines = Lines()
        let sync = BrightnessSync(
            controller: BrightnessController(enumerator: enumerator, backend: backend),
            log: { lines.value.append($0) })
        sync.setMode(mode)
        self.enumerator = enumerator
        self.backend = backend
        self.lines = lines
        self.sync = sync
    }
}

// MARK: - Request path

@MainActor @Test func fullSetOnMainWritesTheOthersToTheSameValue() {
    let rig = Rig(mode: .full)
    #expect(rig.sync.handle(.set(percent: 80, target: .main)) == .ok)
    #expect(rig.backend.percent(3) == 80)
    #expect(rig.backend.percent(2) == 80)
    #expect(rig.sync.lastMain == 80)
}

@MainActor @Test func fullAdjustOnMainWritesTheOthersToTheSameValue() {
    let rig = Rig(mode: .full)
    #expect(rig.sync.handle(.adjust(delta: 20, target: .main)) == .ok)
    #expect(rig.backend.percent(3) == 70)
    #expect(rig.backend.percent(2) == 70)
}

@MainActor @Test func relativeAdjustOnMainMovesTheOthersByTheDelta() {
    let rig = Rig(mode: .relative)
    #expect(rig.sync.handle(.adjust(delta: 10, target: .main)) == .ok)
    #expect(rig.backend.percent(3) == 60)
    #expect(rig.backend.percent(2) == 40)
    #expect(rig.sync.handle(.set(percent: 55, target: .main)) == .ok)
    #expect(rig.backend.percent(2) == 35)
}

@MainActor @Test func relativeDeltaIsMainsActualChangeAfterClamping() {
    let rig = Rig(values: [3: 0.95, 2: 0.5], mode: .relative)
    #expect(rig.sync.handle(.adjust(delta: 10, target: .main)) == .ok)
    #expect(rig.backend.percent(3) == 100)
    #expect(rig.backend.percent(2) == 55)
}

@MainActor @Test func relativeClampOnASecondaryLosesTheDelta() {
    let rig = Rig(values: [3: 0.5, 2: 0.95], mode: .relative)
    #expect(rig.sync.handle(.adjust(delta: 10, target: .main)) == .ok)
    #expect(rig.backend.percent(2) == 100)
    #expect(rig.sync.handle(.adjust(delta: -10, target: .main)) == .ok)
    #expect(rig.backend.percent(2) == 90)
}

@MainActor @Test func setAllWritesEachDisplayOnceAndUpdatesLastMain() {
    let rig = Rig(mode: .relative)
    #expect(rig.sync.handle(.set(percent: 70, target: .all)) == .ok)
    #expect(rig.backend.writes.count == 2)
    #expect(rig.sync.lastMain == 70)
    // The notification for our own write carries the same value: ignored.
    rig.sync.brightnessChanged(id: 3, percent: 70)
    #expect(rig.backend.writes.count == 2)
}

@MainActor @Test func setOnASecondaryTouchesNothingElse() {
    let rig = Rig(mode: .full)
    rig.backend.writes.removeAll()
    #expect(rig.sync.handle(.set(percent: 30, target: .id(2))) == .ok)
    #expect(rig.backend.percent(3) == 50)
    #expect(rig.backend.writes.count == 1)
    #expect(rig.sync.lastMain == 50)
}

@MainActor @Test func offPropagatesNothingButTracksMain() {
    let rig = Rig(mode: .off)
    #expect(rig.sync.handle(.set(percent: 80, target: .main)) == .ok)
    #expect(rig.backend.percent(2) == 30)
    #expect(rig.sync.lastMain == 80)
    rig.sync.brightnessChanged(id: 3, percent: 20)
    #expect(rig.backend.percent(2) == 30)
    #expect(rig.sync.lastMain == 20)
}

@MainActor @Test func repliesMatchTheRequestHandler() {
    let rig = Rig(mode: .full)
    #expect(rig.sync.handle(.readings) == nil)
    #expect(rig.sync.handle(.config) == nil)
    let response = rig.sync.handle(.set(percent: 10, target: .selector("nope")))
    guard case let .failure(error) = response, case .noMatch = error else {
        Issue.record("expected noMatch, got \(String(describing: response))")
        return
    }
}

@MainActor @Test func failingSecondaryIsAPartialFailureInTheReply() {
    let rig = Rig(mode: .full)
    rig.backend.failing = [2]
    let response = rig.sync.handle(.set(percent: 80, target: .main))
    guard case let .failure(error) = response, case let .partialFailure(failures) = error else {
        Issue.record("expected partialFailure, got \(String(describing: response))")
        return
    }
    #expect(failures.count == 1)
    #expect(failures[0].hasPrefix("LG UltraFine:"))
    #expect(rig.backend.percent(3) == 80)
    #expect(rig.sync.lastMain == 80)
}

@MainActor @Test func unsupportedSecondaryIsSkippedSilently() {
    let rig = Rig(mode: .full)
    rig.backend.unsupported = [2]
    rig.backend.writes.removeAll()
    #expect(rig.sync.handle(.set(percent: 80, target: .main)) == .ok)
    #expect(rig.backend.writes.count == 1)
}

// MARK: - Notification path

@MainActor @Test func externalMainChangePropagatesRelative() {
    let rig = Rig(mode: .relative)
    rig.sync.brightnessChanged(id: 3, percent: 60)
    #expect(rig.backend.percent(2) == 40)
    #expect(rig.sync.lastMain == 60)
    rig.sync.brightnessChanged(id: 3, percent: 60)
    #expect(rig.backend.writes.count == 1)
}

@MainActor @Test func externalMainChangePropagatesFull() {
    let rig = Rig(mode: .full)
    rig.backend.writes.removeAll()
    rig.sync.brightnessChanged(id: 3, percent: 60)
    #expect(rig.backend.percent(2) == 60)
}

@MainActor @Test func aChainOfExternalChangesTelescopes() {
    let rig = Rig(mode: .relative)
    for value in [52, 55, 61, 70] { rig.sync.brightnessChanged(id: 3, percent: value) }
    #expect(rig.backend.percent(2) == 50)
}

@MainActor @Test func secondaryNotificationsAreIgnored() {
    let rig = Rig(mode: .full)
    rig.backend.writes.removeAll()
    rig.sync.brightnessChanged(id: 2, percent: 90)
    #expect(rig.backend.writes.isEmpty)
    #expect(rig.sync.lastMain == 50)
}

@MainActor @Test func failingSecondaryOnANotificationIsLogged() {
    let rig = Rig(mode: .full)
    rig.backend.failing = [2]
    rig.sync.brightnessChanged(id: 3, percent: 60)
    #expect(rig.logged.count == 1)
    #expect(rig.logged[0].contains("LG UltraFine"))
    #expect(rig.sync.lastMain == 60)
}

// MARK: - Mode and display changes

@MainActor @Test func switchingToFullSnapsAtOnce() {
    let rig = Rig(mode: .off)
    rig.sync.setMode(.full)
    #expect(rig.backend.percent(2) == 50)
    #expect(rig.sync.mode == .full)
}

@MainActor @Test func switchingToRelativeOrOffChangesNothing() {
    let rig = Rig(mode: .off)
    rig.sync.setMode(.relative)
    rig.sync.setMode(.off)
    #expect(rig.backend.writes.isEmpty)
}

@MainActor @Test func startingInFullSnapsAtOnce() {
    let rig = Rig(mode: .full)
    #expect(rig.backend.percent(2) == 50)
}

@MainActor @Test func displaysChangedPicksUpTheNewMain() {
    let rig = Rig(mode: .relative)
    let newStudio = DisplayInfo(index: 0, id: 3, name: "Studio Display", vendor: "APP", isMain: false)
    let newUltrafine = DisplayInfo(index: 1, id: 2, name: "LG UltraFine", vendor: "GSM", isMain: true)
    rig.enumerator.displays = [newStudio, newUltrafine]
    rig.sync.displaysChanged()
    #expect(rig.sync.lastMain == 30)
    rig.sync.brightnessChanged(id: 2, percent: 40)
    #expect(rig.backend.percent(3) == 60)
}

@MainActor @Test func displaysChangedInFullSnaps() {
    let rig = Rig(mode: .full)
    rig.backend.values[2] = 0.1
    rig.sync.displaysChanged()
    #expect(rig.backend.percent(2) == 50)
}

@MainActor @Test func mainWithoutBrightnessControlLeavesSyncIdle() {
    let rig = Rig(mode: .full)
    rig.backend.unsupported = [3]
    rig.sync.displaysChanged()
    #expect(rig.sync.lastMain == nil)
    rig.backend.writes.removeAll()
    rig.sync.brightnessChanged(id: 3, percent: 60)
    #expect(rig.backend.writes.isEmpty)
    #expect(rig.sync.handle(.set(percent: 20, target: .id(2))) == .ok)
    #expect(rig.backend.writes.count == 1)
}

@MainActor @Test func noDisplaysLeavesSyncIdle() {
    let rig = Rig(mode: .full, displays: [])
    #expect(rig.sync.lastMain == nil)
    rig.sync.brightnessChanged(id: 3, percent: 60)
    #expect(rig.backend.writes.isEmpty)
}
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `./scripts/test.sh --filter MBrightDaemonTests`
Expected: compile error, `BrightnessSync` not found.

- [ ] **Step 5: Implement `BrightnessSync`**

Create `Sources/MBrightDaemon/BrightnessSync.swift`:

```swift
import CoreGraphics
import MBrightCore
import MBrightIPC

/// Makes the other displays follow the main display. Handles `set` and
/// `adjust` ahead of `RequestHandler` so the daemon's own writes to main
/// propagate inside the request; changes made by anyone else arrive
/// through the brightness change notification.
///
/// Main's last known percent is kept in every mode. A notification whose
/// value equals it is the daemon's own write and is ignored; that is the
/// whole loop guard, since a secondary's notification is never acted on.
@MainActor
public final class BrightnessSync {
    public private(set) var mode: SyncMode = .off
    public var lastMain: Int? { main?.percent }

    private let controller: BrightnessController
    private let log: (String) -> Void
    private var main: (id: CGDirectDisplayID, percent: Int)?

    public init(controller: BrightnessController, log: @escaping (String) -> Void) {
        self.controller = controller
        self.log = log
        main = readMain()
    }

    public func setMode(_ new: SyncMode) {
        mode = new
        snap()
    }

    public func displaysChanged() {
        main = readMain()
        snap()
    }

    public func brightnessChanged(id: CGDirectDisplayID, percent: Int) {
        guard let current = main, id == current.id, percent != current.percent else { return }
        main = (id, percent)
        do {
            try propagate(from: current.percent, to: percent)
        } catch {
            log("Warning: sync: \(error)")
        }
    }

    /// `nil` for requests that are not brightness writes.
    public func handle(_ request: Request) -> Response? {
        switch request {
        case let .set(percent, target):
            return respond(target) { try controller.set(percent: percent, target: target) }
        case let .adjust(delta, target):
            return respond(target) { try controller.adjust(delta: delta, target: target) }
        default:
            return nil
        }
    }

    // MARK: - Internals

    /// The write's own errors come back unchanged so the CLI prints what it
    /// printed before. A partial failure still wrote some displays, so the
    /// post-write bookkeeping runs and its failures are added to the list.
    private func respond(_ target: Target, _ write: () throws -> Void) -> Response {
        var failures: [String] = []
        do {
            try write()
        } catch MBrightError.partialFailure(let list) {
            failures = list
        } catch let error as MBrightError {
            return .failure(error)
        } catch {
            return .failure(.daemonFailure("\(error)"))
        }
        do {
            try didWrite(target)
        } catch MBrightError.partialFailure(let list) {
            failures += list
        } catch {
            failures.append("sync: \(error)")
        }
        return failures.isEmpty ? .ok : .failure(.partialFailure(failures: failures))
    }

    /// Refreshes main if it was written; propagates only when main was the
    /// one display written, since `--all` already addressed every display.
    private func didWrite(_ target: Target) throws {
        guard let current = main else { return }
        let written = try controller.resolve(target)
        // A main that cannot be read back keeps its old value; the write's
        // own error already covers that display.
        guard written.contains(where: { $0.id == current.id }),
              let now = try? controller.get(.id(current.id)) else { return }
        main = (current.id, now)
        guard written.count == 1 else { return }
        try propagate(from: current.percent, to: now)
    }

    private func snap() {
        guard mode == .full, let current = main else { return }
        do {
            try propagate(from: current.percent, to: current.percent)
        } catch {
            log("Warning: sync: \(error)")
        }
    }

    private func propagate(from previous: Int, to now: Int) throws {
        guard let current = main, mode != .off else { return }
        if mode == .relative, now == previous { return }
        var failures: [String] = []
        for reading in try controller.readings()
        where reading.display.id != current.id && reading.state != .unsupported {
            let target = Target.id(reading.display.id)
            do {
                if mode == .full {
                    try controller.set(percent: now, target: target)
                } else {
                    try controller.adjust(delta: now - previous, target: target)
                }
            } catch MBrightError.partialFailure(let list) {
                failures += list
            } catch {
                failures.append("\(reading.display.name): \(error)")
            }
        }
        guard failures.isEmpty else { throw MBrightError.partialFailure(failures: failures) }
    }

    private func readMain() -> (id: CGDirectDisplayID, percent: Int)? {
        guard let display = try? controller.resolve(.main).first,
              let percent = try? controller.get(.id(display.id)) else { return nil }
        return (display.id, percent)
    }
}
```

- [ ] **Step 6: Run the tests**

Run: `./scripts/test.sh --filter MBrightDaemonTests`
Expected: all pass. If `relativeDeltaIsMainsActualChangeAfterClamping` fails with 60 instead of 55, `didWrite` is using the requested delta instead of re-reading main; it must read.

- [ ] **Step 7: Run the whole suite and commit**

Run: `./scripts/test.sh`

```bash
git add Sources/MBrightCore/BrightnessController.swift Sources/MBrightDaemon/BrightnessSync.swift Tests/MBrightDaemonTests/Fakes.swift Tests/MBrightDaemonTests/BrightnessSyncTests.swift
git commit -m "feat(daemon): BrightnessSync propagates main display changes"
```

---

### Task 3: `SettingsHandler.onChange`

**Files:**
- Modify: `Sources/MBrightDaemon/SettingsHandler.swift`
- Test: `Tests/MBrightDaemonTests/SettingsHandlerTests.swift`

**Interfaces:**
- Produces: `public var onChange: ((Config) -> Void)?` on `SettingsHandler`, called after a successful `setConfig` or `reloadConfig` with the new config. Not called from `start()`; the daemon reads `settings.config` itself after `start()`.

- [ ] **Step 1: Write the failing test**

Append to `Tests/MBrightDaemonTests/SettingsHandlerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./scripts/test.sh --filter onChangeFires`
Expected: compile error, `onChange` not found.

- [ ] **Step 3: Implement**

In `Sources/MBrightDaemon/SettingsHandler.swift`:

Add after `public private(set) var config = Config()`:

```swift
    /// Called with the new config after a successful set or reload.
    public var onChange: ((Config) -> Void)?
```

Change `set` and `reload` to notify once the config is in place. The reconcile error must still surface, so notify before it:

```swift
    private func set(_ new: Config) throws {
        if new.login, bundle == nil {
            throw MBrightError.loginUnavailable(reason: "mbrightd is running from \(executable)")
        }
        try file.save(new)
        config = new
        onChange?(new)
        try reconcile(.explicit, orReport: "config saved to \(file.path)")
    }

    private func reload() throws {
        config = try file.load() ?? Config()
        onChange?(config)
        try reconcile(.start, orReport: "config reloaded from \(file.path)")
    }
```

- [ ] **Step 4: Run the tests and commit**

Run: `./scripts/test.sh`
Expected: all pass.

```bash
git add Sources/MBrightDaemon/SettingsHandler.swift Tests/MBrightDaemonTests/SettingsHandlerTests.swift
git commit -m "feat(daemon): SettingsHandler reports config changes"
```

---

### Task 4: Wire the sync into `mbrightd`

**Files:**
- Modify: `Sources/mbrightd/MBrightD.swift:28-75`

**Interfaces:**
- Consumes: `BrightnessSync` (Task 2), `SettingsHandler.onChange` (Task 3).

No unit test: this is the composition root, covered by the hardware check in Task 8.

- [ ] **Step 1: Build the sync and route requests through it**

In `Sources/mbrightd/MBrightD.swift`, inside `MainActor.assumeIsolated`, after `settings.start()`, add:

```swift
            let sync = BrightnessSync(controller: controller) {
                FileHandle.standardError.write(Data("\($0)\n".utf8))
            }
            settings.onChange = { sync.setMode($0.sync) }
            sync.setMode(settings.config.sync)
```

Change the server handler so sync runs after settings and before the plain handler:

```swift
            let server = LineServer(path: path, queue: .main) { request in
                if request == .shutdown {
                    // Reply first; the server writes it before this runs.
                    DispatchQueue.main.async { Shutdown.perform() }
                    return .ok
                }
                return MainActor.assumeIsolated {
                    settings.handle(request) ?? sync.handle(request) ?? handler.handle(request)
                }
            }
```

Feed the observer into the sync after the broadcast:

```swift
            let observer = DisplayServicesBrightnessObserver { id, value in
                DispatchQueue.main.async {
                    let percent = Percent.fromDevice(value)
                    server.broadcast(.brightnessChanged(id: id, percent: percent))
                    MainActor.assumeIsolated { sync.brightnessChanged(id: id, percent: percent) }
                }
            }
```

And in the hotplug callback:

```swift
            DisplayWatcher.start {
                observeAll()
                sync.displaysChanged()
                server.broadcast(.displaysChanged)
            }
```

- [ ] **Step 2: Build and run the suite**

Run: `swift build && ./scripts/test.sh`
Expected: clean build, all tests pass. If the compiler complains that `sync` is captured in a `@Sendable` closure, wrap the capture the way `settings` already is: the `LineServer` handler runs on `.main`, so `MainActor.assumeIsolated` is correct there.

- [ ] **Step 3: Smoke test against a scratch daemon**

```bash
export XDG_RUNTIME_DIR=/tmp/mbright-sync XDG_CONFIG_HOME=/tmp/mbright-sync-cfg
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME"
.build/debug/mbrightd &
sleep 1
.build/debug/mbright list
.build/debug/mbright config show
pkill -TERM -f .build/debug/mbrightd
```

Expected: `list` prints both displays, `config show` prints `login`/`ui` lines as before, the daemon exits on SIGTERM.

- [ ] **Step 4: Commit**

```bash
git add Sources/mbrightd/MBrightD.swift
git commit -m "feat(daemon): route brightness writes and notifications through sync"
```

---

### Task 5: CLI `mbright sync` and the `sync:` line

**Files:**
- Modify: `Sources/mbright/ConfigCommands.swift:6-20`
- Modify: `Sources/mbright/MBright.swift:15-20`
- Create: `Sources/mbright/SyncCommand.swift`

**Interfaces:**
- Consumes: `SyncMode`, `Config.sync` (Task 1); `configStatus(_:autostart:)`, `describe(_:)` in `ConfigCommands.swift`.
- Produces: `func syncLine(_ config: Config) -> String`.

The CLI target has no unit tests; verification is by running the binary against a scratch daemon.

- [ ] **Step 1: Add `syncLine` and print it from `describe`**

In `Sources/mbright/ConfigCommands.swift`, add after `loginLine`:

```swift
func syncLine(_ config: Config) -> String {
    switch config.sync {
    case .off: return "sync: off"
    case .full: return "sync: full, other displays match the main display"
    case .relative: return "sync: relative, other displays follow the main display's changes"
    }
}
```

and change `describe` to:

```swift
func describe(_ status: ConfigStatus) -> String {
    let path = abbreviated(status.path)
    return """
        \(path)\(status.onDisk ? "" : " (not written yet)")
        \(loginLine(status.config))
        ui: \(status.config.ui ? "menu bar app" : "mbrightd only")
        \(syncLine(status.config))
        """
}
```

- [ ] **Step 2: Add the command**

Create `Sources/mbright/SyncCommand.swift`:

```swift
import ArgumentParser
import MBrightCore

extension SyncMode: ExpressibleByArgument {}

struct SyncCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Show or set how the other displays follow the main display.",
        discussion: """
            off: every display is adjusted on its own. \
            full: other displays are set to the main display's value. \
            relative: other displays change by the same amount as the main display. \
            Full applies at once; the setting is saved to the config file.
            """
    )

    @Argument(help: "off, full, or relative. Omit to print the current mode.")
    var mode: SyncMode?

    @OptionGroup var daemon: DaemonOptions

    func run() throws {
        // Read first so login and ui survive; only sync changes here.
        var config = try configStatus(.config, autostart: daemon.daemonAutostart).config
        if let mode {
            config.sync = mode
            config = try configStatus(.setConfig(config), autostart: daemon.daemonAutostart).config
        }
        print(syncLine(config))
    }
}
```

Register it in `Sources/mbright/MBright.swift` after `DownCommand.self`:

```swift
            DownCommand.self,
            SyncCommand.self,
            DaemonCommand.self,
```

- [ ] **Step 3: Build and verify by hand**

```bash
swift build
export XDG_RUNTIME_DIR=/tmp/mbright-sync XDG_CONFIG_HOME=/tmp/mbright-sync-cfg
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME"
.build/debug/mbrightd &
sleep 1
.build/debug/mbright sync
.build/debug/mbright sync relative
.build/debug/mbright config show
.build/debug/mbright sync sideways; echo "exit=$?"
cat "$XDG_CONFIG_HOME/mbright/config.json"
.build/debug/mbright sync off
pkill -TERM -f .build/debug/mbrightd
```

Expected, in order: `sync: off`; `sync: relative, ...`; the config block ending in the same relative line; a usage error naming the valid values with exit 64; a JSON file with `"sync" : "relative"`; `sync: off`.

- [ ] **Step 4: Commit**

```bash
git add Sources/mbright/ConfigCommands.swift Sources/mbright/MBright.swift Sources/mbright/SyncCommand.swift
git commit -m "feat(cli): mbright sync shows and sets the sync mode"
```

---

### Task 6: Settings window sync radio group

**Files:**
- Modify: `Sources/MBrightMenuBar/SettingsWindowController.swift`

**Interfaces:**
- Consumes: `SyncMode`, `Config.sync` (Task 1). Uses the existing `.config` / `.setConfig` requests.

No unit test: AppKit view code. Verified by launching the app in Task 8.

- [ ] **Step 1: Rewrite the controller**

Replace the whole of `Sources/MBrightMenuBar/SettingsWindowController.swift` with:

```swift
import AppKit
import Foundation
import MBrightCore
import MBrightIPC

/// A single-pane settings window. Every setting lives in the daemon's
/// config; this window only sends requests and shows what comes back.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    private let launchAtLogin = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let syncButtons: [NSButton]
    private let syncHint = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let connection: DaemonConnection
    private var current = Config()

    private static let syncTitles: [SyncMode: String] = [
        .off: "Off",
        .full: "Full",
        .relative: "Relative",
    ]

    private static let syncHints: [SyncMode: String] = [
        .off: "Each display is adjusted on its own.",
        .full: "Other displays are set to the main display's brightness.",
        .relative: "Other displays change by the same amount as the main display.",
    ]

    init(connection: DaemonConnection) {
        // Every stored property is assigned before `self` is touched.
        self.connection = connection
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        // Radio buttons sharing an action in one superview are mutually
        // exclusive on their own; the tag says which mode each one is.
        syncButtons = SyncMode.allCases.enumerated().map { index, mode in
            let button = NSButton(radioButtonWithTitle: Self.syncTitles[mode] ?? mode.rawValue, target: nil, action: nil)
            button.tag = index
            return button
        }

        window.title = "mbright Settings"
        window.isReleasedWhenClosed = false

        launchAtLogin.target = self
        launchAtLogin.action = #selector(toggleLaunchAtLogin)
        for button in syncButtons {
            button.target = self
            button.action = #selector(selectSync(_:))
        }

        let syncLabel = NSTextField(labelWithString: "Sync with main display")
        syncHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        syncHint.textColor = .secondaryLabelColor
        syncHint.preferredMaxLayoutWidth = 340

        let radios = NSStackView(views: syncButtons)
        radios.orientation = .vertical
        radios.alignment = .leading
        radios.spacing = 4

        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        status.preferredMaxLayoutWidth = 340

        let version = NSTextField(labelWithString: "mbright \(Version.current)")
        version.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        version.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [launchAtLogin, syncLabel, radios, syncHint, status, version])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(16, after: launchAtLogin)
        stack.setCustomSpacing(16, after: syncHint)
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
        window.setContentSize(stack.fittingSize)
    }

    func show() {
        setEnabled(false)
        status.stringValue = "Launch at login takes effect at the next login."
        connection.send(.config) { [weak self] response in
            self?.apply(response)
        }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        var config = current
        config.login = launchAtLogin.state == .on
        send(config)
    }

    @objc private func selectSync(_ sender: NSButton) {
        var config = current
        config.sync = SyncMode.allCases[sender.tag]
        send(config)
    }

    /// Only the changed key differs from what the daemon last reported, so
    /// the other keys survive a change made elsewhere in the meantime.
    private func send(_ config: Config) {
        setEnabled(false)
        connection.send(.setConfig(config)) { [weak self] response in
            self?.apply(response)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        launchAtLogin.isEnabled = enabled
        for button in syncButtons { button.isEnabled = enabled }
    }

    /// The controls always show what the daemon holds, so a failed change
    /// snaps back.
    private func apply(_ response: Response) {
        setEnabled(true)
        switch response {
        case let .config(configStatus):
            current = configStatus.config
            status.stringValue = "Launch at login takes effect at the next login."
        case let .failure(error):
            status.stringValue = "\(error)"
        default:
            status.stringValue = "Unexpected reply from mbrightd."
        }
        launchAtLogin.state = current.login ? .on : .off
        for (index, mode) in SyncMode.allCases.enumerated() {
            syncButtons[index].state = mode == current.sync ? .on : .off
        }
        syncHint.stringValue = Self.syncHints[current.sync] ?? ""
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: clean.

- [ ] **Step 3: Launch and look**

```bash
export XDG_RUNTIME_DIR=/tmp/mbright-sync XDG_CONFIG_HOME=/tmp/mbright-sync-cfg
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME"
.build/debug/mbright-menubar &
sleep 2
osascript -e 'tell application "System Events" to tell process "mbright-menubar" to click menu item "Settings…" of menu 1 of menu bar item 1 of menu bar 1'
sleep 1
screencapture -x /tmp/mbright-settings.png
```

Look at `/tmp/mbright-settings.png`: a checkbox, the "Sync with main display" label, three radios with Off selected, a hint line, the status line, the version, and nothing clipped. Click Relative, then check `cat "$XDG_CONFIG_HOME/mbright/config.json"` shows `"sync" : "relative"`. Then quit the app from its menu (Quit stops the daemon too).

- [ ] **Step 4: Commit**

```bash
git add Sources/MBrightMenuBar/SettingsWindowController.swift
git commit -m "feat(menubar): sync mode radio group in Settings"
```

---

### Task 7: Docs

**Files:**
- Modify: `docs/architecture.md` (Libraries table, Wire protocol note, Notifications, Files table, new section)
- Modify: `docs/cli.md` (synopsis, new `sync` section, `config show` example, Menu bar app paragraph)
- Modify: `README.md:26-36` (usage block)

- [ ] **Step 1: `docs/architecture.md`**

In the Libraries table, change the `MBrightDaemon` row to:

```
| `MBrightDaemon` | Config file, LaunchAgent plist, bundle detection, login reconcile, `SettingsHandler`, `BrightnessSync` |
```

In the Files table, change the Config row's default to `` `{"login": false, "ui": true, "sync": "off"}` ``.

In the Notifications section, after the Brightness paragraph, add:

```
The daemon also feeds every brightness notification to `BrightnessSync`
(below), after broadcasting it.
```

Add a new section before `## Files (XDG Base Directory)`:

```
## Brightness sync

`sync` in the config is `off`, `full` (other displays are set to main's
value) or `relative` (other displays move by main's delta and keep their
own level). `BrightnessSync` in `MBrightDaemon` handles `set` and
`adjust` ahead of `RequestHandler` and keeps main's last known percent
in every mode.

A request that writes main alone propagates inside the request; a
propagation failure comes back as the same `partialFailure` that `--all`
produces. A request that writes main together with other displays
(`--all`) only refreshes the last known value: the user addressed every
display. A brightness notification for main whose value differs from the
last known one is a change made by someone else (keyboard keys, System
Settings, auto-brightness) and propagates, with failures logged to
stderr. An equal value is the daemon's own write and is ignored; a
secondary's notification is never acted on. That is the whole loop
guard.

Switching to `full`, starting with it, reloading into it, and a hotplug
under it all set the other displays to main's value at once. Switching
to `relative` or `off` touches nothing. A main display without
brightness control leaves sync idle. Relative clamps at 0 and 100 and
forgets the lost part of a delta.
```

- [ ] **Step 2: `docs/cli.md`**

In the synopsis block, after the `down` line add:

```
mbright sync [off|full|relative]     other displays follow the main display
```

Add a section after `## set, up, down`:

```
## sync

Without an argument prints the mode. With one, saves it to the config
and prints the result. `full` sets every other display to the main
display's value, at once and on every later change. `relative` moves
every other display by the same amount as the main display and keeps
each display's own level; adjusting a secondary changes its distance
from main. Both react to any change to main: the CLI, the menu bar,
keyboard keys, System Settings, or auto-brightness. `set`, `up` and
`down` with `--all` write every display once; sync does not add to
that. A failed write to a secondary is reported the way `--all` reports
one.
```

In the `config show` example, add a fourth line `sync: off`. In the Menu bar app paragraph, replace "Settings has one option, Launch at login, the same setting as `mbright daemon enable-login`; it takes effect at the next login." with:

```
Settings has Launch at login, the same setting as `mbright daemon
enable-login` (takes effect at the next login), and Sync with main
display, the same setting as `mbright sync`.
```

- [ ] **Step 3: `README.md`**

In the usage block, after `mbright down 10` add:

```
mbright sync relative         # other displays follow the main display's changes
```

- [ ] **Step 4: Commit**

```bash
git add docs/architecture.md docs/cli.md README.md
git commit -m "docs: brightness sync"
```

---

### Task 8: Hardware verification

**Files:** none. This checks the whole feature on the dev machine (Studio Display main, LG UltraFine secondary). The Studio Display has auto-brightness, so assert on the LG.

- [ ] **Step 1: Record current brightness**

```bash
swift build
export XDG_RUNTIME_DIR=/tmp/mbright-sync XDG_CONFIG_HOME=/tmp/mbright-sync-cfg
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME"
.build/debug/mbrightd &
sleep 1
.build/debug/mbright list
```

Note both values to restore later.

- [ ] **Step 2: Relative through the CLI**

```bash
.build/debug/mbright set 40 -d ultrafine
.build/debug/mbright set 50 -d studio
.build/debug/mbright sync relative
.build/debug/mbright up 10            # main only
.build/debug/mbright get -d ultrafine # expect 50
.build/debug/mbright up 10 --all
.build/debug/mbright get -d ultrafine # expect 60, not 70
.build/debug/mbright down 5 -d ultrafine
.build/debug/mbright get -d ultrafine # expect 55; studio unchanged
```

- [ ] **Step 3: Relative through keyboard keys**

Press the brightness-down key once (the Studio Display animates through several notifications). Then:

```bash
.build/debug/mbright list
```

Expected: the LG dropped by the same number of points the Studio Display did, within rounding of one point.

- [ ] **Step 4: Full**

```bash
.build/debug/mbright sync full
.build/debug/mbright list             # LG equals Studio at once
.build/debug/mbright set 45           # main
.build/debug/mbright get -d ultrafine # 45
```

- [ ] **Step 5: Menu bar drag**

```bash
.build/debug/mbright-menubar &
```

Open the menu, drag the Studio Display slider. The LG slider follows in the menu and `mbright get -d ultrafine` matches after the drag. Drag the LG slider: the Studio Display slider stays put. Quit the app from its menu; that stops the daemon.

- [ ] **Step 6: Restore and clean up**

```bash
.build/debug/mbrightd &
sleep 1
.build/debug/mbright sync off
.build/debug/mbright set <studio value from step 1> -d studio
.build/debug/mbright set <lg value from step 1> -d ultrafine
pkill -TERM -f .build/debug/mbrightd
rm -rf /tmp/mbright-sync /tmp/mbright-sync-cfg
```

- [ ] **Step 7: Record the outcome**

Any deviation from the expected values in steps 2 to 5 is a bug to fix before the branch is finished; note the step and the values seen. Nothing to commit if all matched.
