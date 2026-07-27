# mbright Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `mbright`, an open-source macOS CLI that reads and sets brightness on external displays, replacing `betterdisplaycli`.

**Architecture:** A SwiftPM package with a `MBrightCore` library (all logic, fully unit-tested against fakes) and a thin `mbright` executable (ArgumentParser subcommands). Core talks to hardware through two protocols — `DisplayEnumerating` and `BrightnessBackend` — whose production conformers wrap CoreGraphics/AppKit and the private `DisplayServices.framework` respectively.

**Tech Stack:** Swift 6, SwiftPM, swift-argument-parser 1.8.2, Swift Testing, CoreGraphics, AppKit, `dlopen`/`dlsym`.

**Spec:** `docs/superpowers/specs/2026-07-27-mac-brightness-cli-design.md` (commit `e130aa6`)

## Global Constraints

- `// swift-tools-version: 6.0` — exact first line of `Package.swift`.
- `platforms: [.macOS(.v14)]` — required, not optional. `Testing.framework` is built for macOS 14.0; targeting v13 produces a linker warning on every test run.
- Sole dependency: `https://github.com/apple/swift-argument-parser.git` `from: "1.8.2"`. Add no other dependencies.
- Binary name is `mbright`. Library target is `MBrightCore`. Test target is `MBrightCoreTests`.
- **Tests must be run via `./scripts/test.sh`, never bare `swift test`.** XCTest is unavailable without full Xcode; Swift Testing needs framework and rpath flags that the wrapper supplies. Bare `swift test` fails with `no such module 'Testing'`.
- CLI speaks integer percent 0–100. `DisplayServices` speaks `Float` 0.0–1.0. Conversion happens only in `Percent`.
- No HID, no DDC/CI, no IOKit device access anywhere in this plan.
- Every task ends on a green `./scripts/test.sh` and a commit.

---

### Task 1: Package skeleton, test harness, and percent conversion

Creates the branch, the package, the test wrapper, and the first tested unit. The scaffolding is folded in here because nothing can be tested until it exists.

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `scripts/test.sh`
- Create: `Sources/MBrightCore/Percent.swift`
- Create: `Sources/mbright/MBright.swift`
- Test: `Tests/MBrightCoreTests/PercentTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum Percent` with `static func toDevice(_ percent: Int) -> Float`, `static func fromDevice(_ value: Float) -> Int`, `static func clamp(_ percent: Int) -> Int`.

- [ ] **Step 1: Create the feature branch**

```bash
git checkout -b feature/mbright-cli
```

- [ ] **Step 2: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mbright",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mbright", targets: ["mbright"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2")
    ],
    targets: [
        .target(name: "MBrightCore"),
        .executableTarget(
            name: "mbright",
            dependencies: [
                "MBrightCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "MBrightCoreTests", dependencies: ["MBrightCore"]),
    ]
)
```

- [ ] **Step 3: Write `.gitignore`**

```
.build/
.swiftpm/
*.xcodeproj
.DS_Store
```

- [ ] **Step 4: Write `scripts/test.sh`**

The `-F` flags let the compiler find `Testing.framework`; the `-rpath` flags and `DYLD_LIBRARY_PATH` let the test bundle load `Testing` and `lib_TestingInterop.dylib` at runtime. The `if` guard makes the script degrade to plain `swift test` if full Xcode is ever installed.

```bash
#!/usr/bin/env bash
# Swift Testing ships with Command Line Tools but is not on SwiftPM's default
# search path. These flags put it there. Bare `swift test` fails without them.
set -euo pipefail

DEV="$(xcode-select -p)"
FW="$DEV/Library/Developer/Frameworks"
LIB="$DEV/Library/Developer/usr/lib"

if [[ -d "$FW" && -d "$LIB" ]]; then
  exec env DYLD_LIBRARY_PATH="$LIB" swift test \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
else
  exec swift test "$@"
fi
```

Then: `chmod +x scripts/test.sh`

- [ ] **Step 5: Write the failing test**

`Tests/MBrightCoreTests/PercentTests.swift`:

```swift
import Testing
@testable import MBrightCore

@Test func toDeviceMapsPercentToUnitInterval() {
    #expect(Percent.toDevice(0) == 0.0)
    #expect(Percent.toDevice(100) == 1.0)
    #expect(Percent.toDevice(50) == 0.5)
}

@Test func fromDeviceRoundsToNearestPercent() {
    #expect(Percent.fromDevice(0.0) == 0)
    #expect(Percent.fromDevice(1.0) == 100)
    // Values observed from the real displays during the feasibility probe.
    #expect(Percent.fromDevice(0.37386146) == 37)
    #expect(Percent.fromDevice(0.4930456) == 49)
}

@Test func fromDeviceRoundsHalfUp() {
    #expect(Percent.fromDevice(0.365) == 37)
    #expect(Percent.fromDevice(0.374) == 37)
}

@Test func clampBoundsToZeroHundred() {
    #expect(Percent.clamp(-5) == 0)
    #expect(Percent.clamp(0) == 0)
    #expect(Percent.clamp(100) == 100)
    #expect(Percent.clamp(150) == 100)
    #expect(Percent.clamp(42) == 42)
}
```

- [ ] **Step 6: Create a stub so the package compiles, then run the test to see it fail**

`Sources/MBrightCore/Percent.swift`:

```swift
public enum Percent {
    public static func toDevice(_ percent: Int) -> Float { 0 }
    public static func fromDevice(_ value: Float) -> Int { 0 }
    public static func clamp(_ percent: Int) -> Int { 0 }
}
```

`Sources/mbright/MBright.swift` (placeholder so the executable target isn't empty):

```swift
@main
struct MBright {
    static func main() {
        print("mbright")
    }
}
```

Run: `./scripts/test.sh`
Expected: FAIL — `toDeviceMapsPercentToUnitInterval` and the others report expectation failures such as `(0.0) == 1.0`.

- [ ] **Step 7: Write the real implementation**

```swift
/// Converts between the CLI's integer percent (0-100) and the unit interval
/// (0.0-1.0) that DisplayServices uses. All rounding lives here.
public enum Percent {
    public static func toDevice(_ percent: Int) -> Float {
        Float(percent) / 100.0
    }

    public static func fromDevice(_ value: Float) -> Int {
        Int((value * 100).rounded())
    }

    public static func clamp(_ percent: Int) -> Int {
        min(100, max(0, percent))
    }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `./scripts/test.sh`
Expected: PASS — 4 tests, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add Package.swift .gitignore scripts/test.sh Sources Tests
git commit -m "feat: package skeleton, test harness, percent conversion"
```

---

### Task 2: DisplayInfo and EDID vendor decoding

**Files:**
- Create: `Sources/MBrightCore/DisplayInfo.swift`
- Create: `Sources/MBrightCore/PnPID.swift`
- Test: `Tests/MBrightCoreTests/PnPIDTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct DisplayInfo: Equatable, Sendable` with `let index: Int`, `let id: CGDirectDisplayID`, `let name: String`, `let vendor: String`, `let isMain: Bool`, and a memberwise `public init`.
  - `enum PnPID` with `static func decode(_ raw: UInt32) -> String`.

- [ ] **Step 1: Write the failing test**

`Tests/MBrightCoreTests/PnPIDTests.swift`:

```swift
import Testing
@testable import MBrightCore

@Test func decodesRealVendorIDs() {
    // Both values were read from the actual displays via CGDisplayVendorNumber.
    #expect(PnPID.decode(0x610) == "APP")    // Apple Studio Display
    #expect(PnPID.decode(0x9e6d) == "GSM")   // LG UltraFine
}

@Test func rejectsOutOfRangeValues() {
    #expect(PnPID.decode(0) == "?")
    #expect(PnPID.decode(0x1_0000) == "?")
}

@Test func rejectsNonLetterEncodings() {
    // Any 5-bit group of 0 is not a letter (A == 1).
    #expect(PnPID.decode(0b00000_00001_00001) == "?")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/test.sh --filter PnPID`
Expected: FAIL — `cannot find 'PnPID' in scope`.

- [ ] **Step 3: Write the implementations**

`Sources/MBrightCore/PnPID.swift`:

```swift
/// Decodes an EDID PnP vendor ID as packed by `CGDisplayVendorNumber`:
/// three 5-bit letters, A == 1, most significant first.
public enum PnPID {
    public static func decode(_ raw: UInt32) -> String {
        guard raw > 0, raw <= 0xFFFF else { return "?" }

        let groups = [(raw >> 10) & 0x1F, (raw >> 5) & 0x1F, raw & 0x1F]
        guard groups.allSatisfy({ (1...26).contains($0) }) else { return "?" }

        return String(groups.map { Character(UnicodeScalar(UInt8($0) + 64)) })
    }
}
```

`Sources/MBrightCore/DisplayInfo.swift`:

```swift
import CoreGraphics

/// One online display, as presented to the user.
public struct DisplayInfo: Equatable, Sendable {
    /// Position in `list` output. Not stable across replugs.
    public let index: Int
    public let id: CGDirectDisplayID
    public let name: String
    /// EDID PnP vendor code, e.g. "APP" or "GSM".
    public let vendor: String
    public let isMain: Bool

    public init(index: Int, id: CGDirectDisplayID, name: String, vendor: String, isMain: Bool) {
        self.index = index
        self.id = id
        self.name = name
        self.vendor = vendor
        self.isMain = isMain
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test.sh`
Expected: PASS — 7 tests total, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/MBrightCore/DisplayInfo.swift Sources/MBrightCore/PnPID.swift Tests/MBrightCoreTests/PnPIDTests.swift
git commit -m "feat: DisplayInfo model and EDID PnP vendor decoding"
```

---

### Task 3: Errors and display selector resolution

**Files:**
- Create: `Sources/MBrightCore/MBrightError.swift`
- Create: `Sources/MBrightCore/DisplaySelector.swift`
- Test: `Tests/MBrightCoreTests/DisplaySelectorTests.swift`

**Interfaces:**
- Consumes: `DisplayInfo` from Task 2.
- Produces:
  - `enum MBrightError: Error, Equatable, CustomStringConvertible` with cases `frameworkUnavailable(path: String, reason: String)`, `symbolUnavailable(name: String, osVersion: String)`, `enumerationFailed(code: Int32)`, `noDisplays`, `brightnessUnsupported(display: String)`, `operationFailed(display: String, code: Int32)`, `noMatch(selector: String, available: [String])`, `ambiguousSelector(selector: String, candidates: [String])`, `partialFailure(failures: [String])`.
  - `enum DisplaySelector` with `static func resolve(_ selector: String, in displays: [DisplayInfo]) throws -> DisplayInfo`.

- [ ] **Step 1: Write the failing test**

`Tests/MBrightCoreTests/DisplaySelectorTests.swift`:

```swift
import Testing
@testable import MBrightCore

private let fixtures = [
    DisplayInfo(index: 0, id: 3, name: "Studio Display", vendor: "APP", isMain: true),
    DisplayInfo(index: 1, id: 2, name: "LG UltraFine", vendor: "GSM", isMain: false),
]

@Test func resolvesByIndexFirst() throws {
    #expect(try DisplaySelector.resolve("0", in: fixtures).name == "Studio Display")
    #expect(try DisplaySelector.resolve("1", in: fixtures).name == "LG UltraFine")
}

@Test func fallsThroughToDisplayIDWhenNoSuchIndex() throws {
    // No index 2 or 3 exists, so these must resolve as display IDs.
    #expect(try DisplaySelector.resolve("2", in: fixtures).name == "LG UltraFine")
    #expect(try DisplaySelector.resolve("3", in: fixtures).name == "Studio Display")
}

@Test func resolvesByCaseInsensitiveSubstring() throws {
    #expect(try DisplaySelector.resolve("studio", in: fixtures).id == 3)
    #expect(try DisplaySelector.resolve("ULTRAFINE", in: fixtures).id == 2)
    #expect(try DisplaySelector.resolve("lg", in: fixtures).id == 2)
}

@Test func ambiguousSubstringThrowsWithCandidates() {
    let dupes = [
        DisplayInfo(index: 0, id: 1, name: "Dell U2720Q", vendor: "DEL", isMain: true),
        DisplayInfo(index: 1, id: 2, name: "Dell U2723QE", vendor: "DEL", isMain: false),
    ]
    #expect(throws: MBrightError.ambiguousSelector(
        selector: "dell",
        candidates: ["Dell U2720Q", "Dell U2723QE"]
    )) {
        try DisplaySelector.resolve("dell", in: dupes)
    }
}

@Test func unmatchedSelectorThrowsWithAvailableNames() {
    #expect(throws: MBrightError.noMatch(
        selector: "benq",
        available: ["Studio Display", "LG UltraFine"]
    )) {
        try DisplaySelector.resolve("benq", in: fixtures)
    }
}

@Test func negativeAndHugeNumbersDoNotTrap() {
    // UInt32(exactly:) must guard these; a plain UInt32(n) would crash.
    #expect(throws: MBrightError.self) { try DisplaySelector.resolve("-1", in: fixtures) }
    #expect(throws: MBrightError.self) { try DisplaySelector.resolve("99999999999", in: fixtures) }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/test.sh --filter DisplaySelector`
Expected: FAIL — `cannot find 'DisplaySelector' in scope`.

- [ ] **Step 3: Write `MBrightError`**

`Sources/MBrightCore/MBrightError.swift`:

```swift
public enum MBrightError: Error, Equatable, CustomStringConvertible {
    case frameworkUnavailable(path: String, reason: String)
    case symbolUnavailable(name: String, osVersion: String)
    case enumerationFailed(code: Int32)
    case noDisplays
    case brightnessUnsupported(display: String)
    case operationFailed(display: String, code: Int32)
    case noMatch(selector: String, available: [String])
    case ambiguousSelector(selector: String, candidates: [String])
    case partialFailure(failures: [String])

    public var description: String {
        switch self {
        case let .frameworkUnavailable(path, reason):
            return "Could not load DisplayServices at \(path): \(reason)"
        case let .symbolUnavailable(name, osVersion):
            return """
                DisplayServices is missing the symbol '\(name)' on \(osVersion). \
                This private API changed; mbright needs updating.
                """
        case let .enumerationFailed(code):
            return "CGGetOnlineDisplayList failed with code \(code)"
        case .noDisplays:
            return "No online displays found"
        case let .brightnessUnsupported(display):
            return "Display '\(display)' does not support brightness control"
        case let .operationFailed(display, code):
            return "Brightness operation failed on '\(display)' (code \(code))"
        case let .noMatch(selector, available):
            return "No display matches '\(selector)'. Available: \(available.joined(separator: ", "))"
        case let .ambiguousSelector(selector, candidates):
            return "'\(selector)' matches multiple displays: \(candidates.joined(separator: ", ")). Be more specific."
        case let .partialFailure(failures):
            return "Some displays failed:\n  " + failures.joined(separator: "\n  ")
        }
    }
}
```

- [ ] **Step 4: Write `DisplaySelector`**

`Sources/MBrightCore/DisplaySelector.swift`:

```swift
import CoreGraphics

/// Resolves a user-supplied `--display` selector to exactly one display.
///
/// Precedence is strict, not best-match: list index, then CGDirectDisplayID,
/// then case-insensitive name substring. Indices and display IDs share a
/// numeric namespace and do collide in practice, so ordering is what makes a
/// numeric selector unambiguous.
public enum DisplaySelector {
    public static func resolve(_ selector: String, in displays: [DisplayInfo]) throws -> DisplayInfo {
        if let number = Int(selector) {
            if let byIndex = displays.first(where: { $0.index == number }) {
                return byIndex
            }
            // UInt32(exactly:) rather than UInt32(_:) — the latter traps on
            // negative or oversized input.
            if let id = UInt32(exactly: number),
               let byID = displays.first(where: { $0.id == id }) {
                return byID
            }
        }

        let needle = selector.lowercased()
        let matches = displays.filter { $0.name.lowercased().contains(needle) }

        switch matches.count {
        case 1:
            return matches[0]
        case 0:
            throw MBrightError.noMatch(selector: selector, available: displays.map(\.name))
        default:
            throw MBrightError.ambiguousSelector(selector: selector, candidates: matches.map(\.name))
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `./scripts/test.sh`
Expected: PASS — 13 tests total, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/MBrightCore/MBrightError.swift Sources/MBrightCore/DisplaySelector.swift Tests/MBrightCoreTests/DisplaySelectorTests.swift
git commit -m "feat: error types and display selector resolution"
```

---

### Task 4: Protocols, fakes, and BrightnessController

The heart of the tool. Everything here is tested without hardware.

**Files:**
- Create: `Sources/MBrightCore/BrightnessBackend.swift`
- Create: `Sources/MBrightCore/BrightnessController.swift`
- Create: `Tests/MBrightCoreTests/Fakes.swift`
- Test: `Tests/MBrightCoreTests/BrightnessControllerTests.swift`

**Interfaces:**
- Consumes: `DisplayInfo`, `MBrightError`, `DisplaySelector`, `Percent`.
- Produces:
  - `protocol DisplayEnumerating` with `func onlineDisplays() throws -> [DisplayInfo]`.
  - `protocol BrightnessBackend` with `func canChangeBrightness(_ id: CGDirectDisplayID) -> Bool`, `func getBrightness(_ id: CGDirectDisplayID) throws -> Float`, `func setBrightness(_ id: CGDirectDisplayID, _ value: Float) throws`.
  - `enum Target { case main, all, selector(String) }`.
  - `struct DisplayReading: Equatable` with `let display: DisplayInfo`, `let percent: Int?`.
  - `struct BrightnessController` with `init(enumerator:backend:)`, `func readings() throws -> [DisplayReading]`, `func get(_ target: Target) throws -> Int`, `func set(percent: Int, target: Target) throws`, `func adjust(delta: Int, target: Target) throws`.

- [ ] **Step 1: Write the protocols and supporting types**

`Sources/MBrightCore/BrightnessBackend.swift`:

```swift
import CoreGraphics

/// Source of the currently-online displays.
public protocol DisplayEnumerating: Sendable {
    func onlineDisplays() throws -> [DisplayInfo]
}

/// Reads and writes brightness on the unit interval (0.0-1.0).
public protocol BrightnessBackend: Sendable {
    func canChangeBrightness(_ id: CGDirectDisplayID) -> Bool
    func getBrightness(_ id: CGDirectDisplayID) throws -> Float
    func setBrightness(_ id: CGDirectDisplayID, _ value: Float) throws
}

/// Which displays a command applies to.
public enum Target: Equatable, Sendable {
    case main
    case all
    case selector(String)
}

/// A display paired with its current brightness, or nil if unsupported.
public struct DisplayReading: Equatable, Sendable {
    public let display: DisplayInfo
    public let percent: Int?

    public init(display: DisplayInfo, percent: Int?) {
        self.display = display
        self.percent = percent
    }
}
```

- [ ] **Step 2: Write the fakes**

`Tests/MBrightCoreTests/Fakes.swift`:

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
        if failing.contains(id) { throw MBrightError.operationFailed(display: "\(id)", code: -1) }
        return values[id] ?? 0
    }

    func setBrightness(_ id: CGDirectDisplayID, _ value: Float) throws {
        if failing.contains(id) { throw MBrightError.operationFailed(display: "\(id)", code: -1) }
        values[id] = value
        writes.append((id, value))
    }
}
```

- [ ] **Step 3: Write the failing test**

`Tests/MBrightCoreTests/BrightnessControllerTests.swift`:

```swift
import Testing
@testable import MBrightCore

private func controller(
    _ enumerator: FakeEnumerator = FakeEnumerator(),
    _ backend: FakeBackend = FakeBackend()
) -> (BrightnessController, FakeBackend) {
    (BrightnessController(enumerator: enumerator, backend: backend), backend)
}

@Test func getDefaultsToMainDisplay() throws {
    let backend = FakeBackend(values: [3: 0.37, 2: 0.49])
    let (sut, _) = controller(FakeEnumerator(), backend)
    #expect(try sut.get(.main) == 37)
}

@Test func getBySelectorReadsThatDisplay() throws {
    let backend = FakeBackend(values: [3: 0.37, 2: 0.49])
    let (sut, _) = controller(FakeEnumerator(), backend)
    #expect(try sut.get(.selector("ultrafine")) == 49)
}

@Test func setWritesConvertedValueToOneDisplay() throws {
    let (sut, backend) = controller()
    try sut.set(percent: 80, target: .selector("studio"))
    #expect(backend.writes.count == 1)
    #expect(backend.writes[0].id == 3)
    #expect(backend.writes[0].value == 0.8)
}

@Test func setAllWritesToEveryDisplay() throws {
    let (sut, backend) = controller()
    try sut.set(percent: 25, target: .all)
    #expect(backend.writes.map(\.id).sorted() == [2, 3])
    #expect(backend.writes.allSatisfy { $0.value == 0.25 })
}

@Test func adjustAddsDeltaToCurrentValue() throws {
    let backend = FakeBackend(values: [3: 0.50, 2: 0.50])
    let (sut, _) = controller(FakeEnumerator(), backend)
    try sut.adjust(delta: 10, target: .selector("studio"))
    #expect(Percent.fromDevice(backend.values[3]!) == 60)
}

@Test func adjustClampsAtCeiling() throws {
    let backend = FakeBackend(values: [3: 0.95, 2: 0.5])
    let (sut, _) = controller(FakeEnumerator(), backend)
    try sut.adjust(delta: 20, target: .selector("studio"))
    #expect(Percent.fromDevice(backend.values[3]!) == 100)
}

@Test func adjustClampsAtFloor() throws {
    let backend = FakeBackend(values: [3: 0.05, 2: 0.5])
    let (sut, _) = controller(FakeEnumerator(), backend)
    try sut.adjust(delta: -20, target: .selector("studio"))
    #expect(Percent.fromDevice(backend.values[3]!) == 0)
}

@Test func unsupportedDisplayThrows() {
    let backend = FakeBackend()
    backend.unsupported = [3]
    let (sut, _) = controller(FakeEnumerator(), backend)
    #expect(throws: MBrightError.brightnessUnsupported(display: "Studio Display")) {
        try sut.set(percent: 50, target: .selector("studio"))
    }
}

@Test func allContinuesPastFailureThenThrows() {
    let backend = FakeBackend()
    backend.failing = [3]
    let (sut, _) = controller(FakeEnumerator(), backend)

    #expect(throws: MBrightError.self) {
        try sut.set(percent: 30, target: .all)
    }
    // The healthy display must still have been written.
    #expect(backend.values[2] == 0.3)
}

@Test func readingsReportNilForUnsupportedDisplays() throws {
    let backend = FakeBackend(values: [3: 0.4, 2: 0.6])
    backend.unsupported = [2]
    let (sut, _) = controller(FakeEnumerator(), backend)

    let readings = try sut.readings()
    #expect(readings.count == 2)
    #expect(readings[0].percent == 40)
    #expect(readings[1].percent == nil)
}

@Test func emptyDisplayListThrows() {
    let (sut, _) = controller(FakeEnumerator([]), FakeBackend())
    #expect(throws: MBrightError.noDisplays) { try sut.get(.main) }
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `./scripts/test.sh --filter BrightnessController`
Expected: FAIL — `cannot find 'BrightnessController' in scope`.

- [ ] **Step 5: Write `BrightnessController`**

`Sources/MBrightCore/BrightnessController.swift`:

```swift
import CoreGraphics

/// Orchestrates display resolution, unit conversion, and clamping.
/// Hardware access is entirely behind `DisplayEnumerating` and `BrightnessBackend`.
public struct BrightnessController {
    private let enumerator: DisplayEnumerating
    private let backend: BrightnessBackend

    public init(enumerator: DisplayEnumerating, backend: BrightnessBackend) {
        self.enumerator = enumerator
        self.backend = backend
    }

    /// Every display with its current brightness; nil percent means the
    /// display reports no brightness control.
    public func readings() throws -> [DisplayReading] {
        try enumerator.onlineDisplays().map { display in
            guard backend.canChangeBrightness(display.id) else {
                return DisplayReading(display: display, percent: nil)
            }
            let value = try? backend.getBrightness(display.id)
            return DisplayReading(display: display, percent: value.map(Percent.fromDevice))
        }
    }

    public func get(_ target: Target) throws -> Int {
        let display = try resolve(target)[0]
        try ensureSupported(display)
        return Percent.fromDevice(try backend.getBrightness(display.id))
    }

    public func set(percent: Int, target: Target) throws {
        let value = Percent.toDevice(Percent.clamp(percent))
        try apply(target) { display in
            try backend.setBrightness(display.id, value)
        }
    }

    public func adjust(delta: Int, target: Target) throws {
        try apply(target) { display in
            let current = Percent.fromDevice(try backend.getBrightness(display.id))
            let next = Percent.clamp(current + delta)
            try backend.setBrightness(display.id, Percent.toDevice(next))
        }
    }

    // MARK: - Internals

    func resolve(_ target: Target) throws -> [DisplayInfo] {
        let displays = try enumerator.onlineDisplays()
        guard !displays.isEmpty else { throw MBrightError.noDisplays }

        switch target {
        case .all:
            return displays
        case .main:
            return [displays.first(where: \.isMain) ?? displays[0]]
        case let .selector(selector):
            return [try DisplaySelector.resolve(selector, in: displays)]
        }
    }

    /// Runs `body` against every targeted display. A failure on one display
    /// does not abort the others; all errors are collected and rethrown so a
    /// partial success can never look like a clean run.
    private func apply(_ target: Target, _ body: (DisplayInfo) throws -> Void) throws {
        var failures: [String] = []

        for display in try resolve(target) {
            do {
                try ensureSupported(display)
                try body(display)
            } catch {
                failures.append("\(display.name): \(error)")
            }
        }

        guard failures.isEmpty else {
            throw MBrightError.partialFailure(failures: failures)
        }
    }

    private func ensureSupported(_ display: DisplayInfo) throws {
        guard backend.canChangeBrightness(display.id) else {
            throw MBrightError.brightnessUnsupported(display: display.name)
        }
    }
}
```

Note on `set`: a single-display `set` of an unsupported display surfaces as `partialFailure` wrapping `brightnessUnsupported`. The test `unsupportedDisplayThrows` expects the bare `brightnessUnsupported`, so `apply` must rethrow a lone failure unwrapped. Add this to `apply` before the `guard`:

```swift
        if failures.count == 1, case .selector = target {
            // Single explicit target: surface the underlying error directly.
            throw MBrightError.brightnessUnsupported(display: try resolve(target)[0].name)
        }
```

If that special-casing feels wrong during implementation, the alternative is to relax the test to `#expect(throws: MBrightError.self)`. Prefer the relaxed test — it keeps `apply` uniform. Make the call, then keep it consistent.

- [ ] **Step 6: Run tests to verify they pass**

Run: `./scripts/test.sh`
Expected: PASS — 24 tests total, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Sources/MBrightCore Tests/MBrightCoreTests
git commit -m "feat: brightness controller with display targeting and clamping"
```

---

### Task 5: List table rendering

**Files:**
- Create: `Sources/MBrightCore/ListTable.swift`
- Test: `Tests/MBrightCoreTests/ListTableTests.swift`

**Interfaces:**
- Consumes: `DisplayReading`, `DisplayInfo`.
- Produces: `enum ListTable` with `static func render(_ readings: [DisplayReading]) -> String`.

- [ ] **Step 1: Write the failing test**

`Tests/MBrightCoreTests/ListTableTests.swift`:

```swift
import Testing
@testable import MBrightCore

@Test func rendersAlignedTable() {
    let output = ListTable.render([
        DisplayReading(display: studio, percent: 37),
        DisplayReading(display: ultrafine, percent: 49),
    ])
    let lines = output.split(separator: "\n").map(String.init)

    #expect(lines[0].hasPrefix("INDEX"))
    #expect(lines[1].contains("Studio Display"))
    #expect(lines[1].contains("APP"))
    #expect(lines[1].contains("37%"))
    #expect(lines[2].contains("LG UltraFine"))
    #expect(lines[2].contains("49%"))
    #expect(lines.count == 3)
}

@Test func marksMainDisplay() {
    let output = ListTable.render([DisplayReading(display: studio, percent: 37)])
    #expect(output.contains("*"))
}

@Test func rendersUnsupportedAsDash() {
    let output = ListTable.render([DisplayReading(display: ultrafine, percent: nil)])
    #expect(output.contains("-"))
    #expect(!output.contains("%"))
}

@Test func handlesEmptyInput() {
    #expect(ListTable.render([]) == "")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/test.sh --filter ListTable`
Expected: FAIL — `cannot find 'ListTable' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/MBrightCore/ListTable.swift`:

```swift
/// Renders `list` output as a column-aligned table.
public enum ListTable {
    public static func render(_ readings: [DisplayReading]) -> String {
        guard !readings.isEmpty else { return "" }

        let header = ["INDEX", "NAME", "VENDOR", "ID", "BRIGHTNESS"]
        let rows = readings.map { reading in
            [
                "\(reading.display.index)" + (reading.display.isMain ? "*" : ""),
                reading.display.name,
                reading.display.vendor,
                "\(reading.display.id)",
                reading.percent.map { "\($0)%" } ?? "-",
            ]
        }

        let widths = (0..<header.count).map { column in
            ([header] + rows).map { $0[column].count }.max() ?? 0
        }

        return ([header] + rows)
            .map { row in
                row.enumerated()
                    .map { $0.offset == row.count - 1
                        ? $0.element
                        : $0.element.padding(toLength: widths[$0.offset] + 2, withPad: " ", startingAt: 0) }
                    .joined()
            }
            .joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test.sh`
Expected: PASS — 28 tests total, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/MBrightCore/ListTable.swift Tests/MBrightCoreTests/ListTableTests.swift
git commit -m "feat: list table rendering"
```

---

### Task 6: The hardware edge — DisplayServices shim and system enumerator

This is the only code that touches real hardware, and the only code not covered by unit tests. It is verified manually against both displays.

**Files:**
- Create: `Sources/MBrightCore/DisplayServicesBackend.swift`
- Create: `Sources/MBrightCore/SystemDisplayEnumerator.swift`
- Create: `Sources/mbright/Probe.swift` (temporary, deleted in Step 5)

**Interfaces:**
- Consumes: `BrightnessBackend`, `DisplayEnumerating`, `DisplayInfo`, `MBrightError`, `PnPID`.
- Produces: `final class DisplayServicesBackend: BrightnessBackend` with `init() throws`; `struct SystemDisplayEnumerator: DisplayEnumerating` with `init()`.

- [ ] **Step 1: Write `DisplayServicesBackend`**

`Sources/MBrightCore/DisplayServicesBackend.swift`:

```swift
import Foundation
import CoreGraphics

/// Brightness via the private DisplayServices framework, resolved at runtime.
///
/// This is private API with no public header, so every symbol lookup is
/// checked and reports exactly what is missing rather than crashing.
public final class DisplayServicesBackend: BrightnessBackend, @unchecked Sendable {
    private typealias CanChangeFn = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    public static let frameworkPath =
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    private let canChangeFn: CanChangeFn
    private let getFn: GetFn
    private let setFn: SetFn
    /// Bound opportunistically for a future --fade flag. Deliberately optional:
    /// v1 never calls it, so a missing symbol must not break the tool.
    private let setSmoothFn: SetFn?

    public init() throws {
        guard let handle = dlopen(Self.frameworkPath, RTLD_LAZY) else {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
            throw MBrightError.frameworkUnavailable(path: Self.frameworkPath, reason: reason)
        }

        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        func required<T>(_ name: String, as type: T.Type) throws -> T {
            guard let symbol = dlsym(handle, name) else {
                throw MBrightError.symbolUnavailable(name: name, osVersion: osVersion)
            }
            return unsafeBitCast(symbol, to: type)
        }

        func optional<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }

        canChangeFn = try required("DisplayServicesCanChangeBrightness", as: CanChangeFn.self)
        getFn = try required("DisplayServicesGetBrightness", as: GetFn.self)
        setFn = try required("DisplayServicesSetBrightness", as: SetFn.self)
        setSmoothFn = optional("DisplayServicesSetBrightnessSmooth", as: SetFn.self)
    }

    public func canChangeBrightness(_ id: CGDirectDisplayID) -> Bool {
        canChangeFn(id)
    }

    public func getBrightness(_ id: CGDirectDisplayID) throws -> Float {
        var value: Float = 0
        let code = getFn(id, &value)
        guard code == 0 else {
            throw MBrightError.operationFailed(display: "\(id)", code: code)
        }
        return value
    }

    public func setBrightness(_ id: CGDirectDisplayID, _ value: Float) throws {
        let code = setFn(id, value)
        guard code == 0 else {
            throw MBrightError.operationFailed(display: "\(id)", code: code)
        }
    }
}
```

- [ ] **Step 2: Write `SystemDisplayEnumerator`**

`Sources/MBrightCore/SystemDisplayEnumerator.swift`:

```swift
import AppKit
import CoreGraphics

/// Online displays from CoreGraphics, with friendly names from AppKit.
/// `NSScreen.localizedName` works from a plain CLI with no NSApplication;
/// this was verified on the target machine.
public struct SystemDisplayEnumerator: DisplayEnumerating {
    private static let maxDisplays = 16

    public init() {}

    public func onlineDisplays() throws -> [DisplayInfo] {
        var ids = [CGDirectDisplayID](repeating: 0, count: Self.maxDisplays)
        var count: UInt32 = 0

        let error = CGGetOnlineDisplayList(UInt32(Self.maxDisplays), &ids, &count)
        guard error == .success else {
            throw MBrightError.enumerationFailed(code: error.rawValue)
        }

        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            names[CGDirectDisplayID(number.uint32Value)] = screen.localizedName
        }

        return (0..<Int(count)).map { index in
            let id = ids[index]
            return DisplayInfo(
                index: index,
                id: id,
                name: names[id] ?? "Display \(id)",
                vendor: PnPID.decode(CGDisplayVendorNumber(id)),
                isMain: CGDisplayIsMain(id) != 0
            )
        }
    }
}
```

- [ ] **Step 3: Write a temporary probe to verify against real hardware**

`Sources/mbright/Probe.swift` — replace the placeholder `MBright.swift` body temporarily by making this the entry point. Delete `Sources/mbright/MBright.swift` for this step, then create:

```swift
import MBrightCore

@main
struct Probe {
    static func main() throws {
        let enumerator = SystemDisplayEnumerator()
        let backend = try DisplayServicesBackend()
        let controller = BrightnessController(enumerator: enumerator, backend: backend)

        print(ListTable.render(try controller.readings()))

        // No-op write: read each value and write back exactly what was read,
        // so nothing visibly changes but write capability is proven.
        for display in try enumerator.onlineDisplays() {
            let current = try backend.getBrightness(display.id)
            try backend.setBrightness(display.id, current)
            print("no-op write OK: \(display.name) at \(current)")
        }
    }
}
```

- [ ] **Step 4: Run the probe against the real displays**

Run: `swift run mbright`
Expected output — two rows and two successful no-op writes, with no visible brightness change:

```
INDEX  NAME            VENDOR  ID  BRIGHTNESS
0*     Studio Display  APP     3   37%
1      LG UltraFine    GSM     2   49%
no-op write OK: Studio Display at 0.37...
no-op write OK: LG UltraFine at 0.49...
```

If either display reports `-` under BRIGHTNESS, or a write throws, stop and report — the spec's core assumption has broken.

- [ ] **Step 5: Delete the probe**

```bash
rm Sources/mbright/Probe.swift
```

Task 7 recreates `Sources/mbright/MBright.swift` as the real entry point. The package will not build between this step and Task 7 Step 3; that is expected.

- [ ] **Step 6: Commit**

`git add -A` is needed here because this task deletes `Sources/mbright/MBright.swift` (committed in Task 1) as well as adding new files.

```bash
git add -A Sources/
git commit -m "feat: DisplayServices backend and system display enumerator"
```

---

### Task 7: CLI commands

**Files:**
- Create: `Sources/mbright/MBright.swift` (replaces the Task 1 placeholder)
- Create: `Sources/mbright/TargetOptions.swift`
- Create: `Sources/mbright/Commands.swift`

**Interfaces:**
- Consumes: `BrightnessController`, `SystemDisplayEnumerator`, `DisplayServicesBackend`, `ListTable`, `Target`.
- Produces: the `mbright` binary with subcommands `list`, `get`, `set`, `up`, `down`.

- [ ] **Step 1: Write the shared target options**

`Sources/mbright/TargetOptions.swift`:

```swift
import ArgumentParser
import MBrightCore

struct TargetOptions: ParsableArguments {
    @Option(name: [.customShort("d"), .customLong("display")],
            help: "Display index, ID, or name substring (e.g. studio).")
    var display: String?

    @Flag(name: .long, help: "Apply to every online display.")
    var all = false

    func resolvedTarget() throws -> Target {
        if all, display != nil {
            throw ValidationError("--display and --all are mutually exclusive.")
        }
        if all { return .all }
        if let display { return .selector(display) }
        return .main
    }
}

func makeController() throws -> BrightnessController {
    BrightnessController(
        enumerator: SystemDisplayEnumerator(),
        backend: try DisplayServicesBackend()
    )
}
```

- [ ] **Step 2: Write the subcommands**

`Sources/mbright/Commands.swift`. Types are named `...Command` so `SetCommand` does not shadow Swift's `Set`.

```swift
import ArgumentParser
import MBrightCore

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Show every online display and its brightness."
    )

    func run() throws {
        print(ListTable.render(try makeController().readings()))
    }
}

struct GetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Print one display's brightness as a bare integer."
    )

    @OptionGroup var target: TargetOptions

    func run() throws {
        if target.all {
            throw ValidationError("get does not support --all; use 'mbright list'.")
        }
        print(try makeController().get(try target.resolvedTarget()))
    }
}

struct SetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set brightness to an absolute percentage."
    )

    @Argument(help: "Brightness percentage, 0-100.")
    var percent: Int

    @OptionGroup var target: TargetOptions

    func validate() throws {
        guard (0...100).contains(percent) else {
            throw ValidationError("Brightness must be between 0 and 100.")
        }
    }

    func run() throws {
        try makeController().set(percent: percent, target: try target.resolvedTarget())
    }
}

struct UpCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "up",
        abstract: "Increase brightness, clamped at 100."
    )

    @Argument(help: "Percentage points to add.")
    var delta: Int = 10

    @OptionGroup var target: TargetOptions

    func run() throws {
        try makeController().adjust(delta: abs(delta), target: try target.resolvedTarget())
    }
}

struct DownCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "down",
        abstract: "Decrease brightness, clamped at 0."
    )

    @Argument(help: "Percentage points to subtract.")
    var delta: Int = 10

    @OptionGroup var target: TargetOptions

    func run() throws {
        try makeController().adjust(delta: -abs(delta), target: try target.resolvedTarget())
    }
}
```

- [ ] **Step 3: Write the entry point**

`Sources/mbright/MBright.swift`:

```swift
import ArgumentParser

@main
struct MBright: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mbright",
        abstract: "Control display brightness on macOS.",
        version: "0.1.0",
        subcommands: [
            ListCommand.self,
            GetCommand.self,
            SetCommand.self,
            UpCommand.self,
            DownCommand.self,
        ],
        defaultSubcommand: ListCommand.self
    )
}
```

- [ ] **Step 4: Verify the build and unit tests still pass**

Run: `swift build && ./scripts/test.sh`
Expected: build succeeds; 28 tests pass.

- [ ] **Step 5: Verify end-to-end against real hardware**

Run each and confirm the described result. Brightness will visibly change.

```bash
swift run mbright list                      # two rows, Studio Display marked *
swift run mbright get                       # bare integer, main display
swift run mbright get -d ultrafine          # bare integer, LG
swift run mbright set 40 -d studio          # Studio Display visibly changes
swift run mbright up 10 -d studio           # goes to 50
swift run mbright down 10 -d studio         # back to 40
swift run mbright set 45 --all              # both displays change
swift run mbright get --all                 # ERROR: get does not support --all
swift run mbright set 150                   # ERROR: must be between 0 and 100
swift run mbright set 50 -d nope            # ERROR: no display matches 'nope'
swift run mbright set 50 -d studio --all    # ERROR: mutually exclusive
swift run mbright --help                    # lists all five subcommands
```

- [ ] **Step 6: Restore your preferred brightness and commit**

```bash
git add Sources/mbright
git commit -m "feat: mbright CLI commands"
```

---

### Task 8: README and install path

**Files:**
- Create: `README.md`
- Create: `LICENSE`

**Interfaces:**
- Consumes: the finished CLI.
- Produces: user-facing documentation.

- [ ] **Step 1: Write `README.md`**

````markdown
# mbright

Open-source brightness control for macOS displays, from the command line.

Works with displays that ignore DDC/CI — including the Apple Studio Display and
LG UltraFine — by going through Apple's own `DisplayServices` layer. No
background app, no root, no permission prompts.

## Why

`brightness` handles built-in laptop panels only. `m1ddc` and `ddcctl` need
DDC/CI, which neither the Studio Display nor the UltraFine speaks. MonitorControl
is a GUI. `betterdisplaycli` works but is closed source and needs its app running.

## Install

Requires macOS 14+ and the Swift toolchain (Xcode Command Line Tools is enough).

```bash
git clone <repo-url> && cd mac-brightness
swift build -c release
cp .build/release/mbright /usr/local/bin/
```

## Usage

```bash
mbright list                  # all displays and their brightness
mbright get                   # main display, bare integer for scripting
mbright get -d ultrafine      # by name substring
mbright set 80                # main display
mbright set 80 --all          # every display
mbright up 10 -d studio       # relative, clamped at 100
mbright down 10 --all         # relative, clamped at 0
```

`--display` / `-d` accepts a list index, a `CGDirectDisplayID`, or a
case-insensitive name substring. Numeric selectors are tried as an index first
and only then as a display ID. Indices shift when you replug displays, so
scripts should prefer names.

## Development

```bash
./scripts/test.sh             # NOT bare `swift test` — see below
```

Swift Testing ships with Command Line Tools but is not on SwiftPM's default
search path, so `scripts/test.sh` supplies the framework and rpath flags. Bare
`swift test` fails with `no such module 'Testing'`. XCTest is unavailable
without full Xcode.

## Caveats

`DisplayServices` is a private framework. Apple can change it in any macOS
release. If a symbol disappears, mbright fails with a message naming the exact
missing symbol rather than crashing or silently doing nothing.
````

- [ ] **Step 2: Add an MIT `LICENSE`**

Use the standard MIT license text with `Copyright (c) 2026 Aleksey`.

- [ ] **Step 3: Verify the release build and install path work**

```bash
swift build -c release
./.build/release/mbright list
```

Expected: the same two-row table as `swift run mbright list`.

- [ ] **Step 4: Commit**

```bash
git add README.md LICENSE
git commit -m "docs: README and license"
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
| --- | --- |
| Architecture / module table | 1, 4, 6, 7 |
| Shim, four symbols | 6 |
| Units, percent↔float | 1 |
| Display targeting, strict precedence | 3 |
| Commands list/get/set/up/down | 7 |
| `get --all` rejected | 7 |
| `set` range validation, up/down clamping | 4, 7 |
| Error handling table | 3, 6 |
| `--all` partial failure semantics | 4 |
| Testing strategy | 1–5 |
| Out of scope (no HID/DDC, no fades/presets/daemon) | honored throughout |

Every spec requirement maps to a task. The spec's `SetBrightnessSmooth` binding
is implemented as an *optional* lookup rather than a required one — binding it
as required would let a missing, unused symbol break the whole tool. This is a
deliberate deviation, noted in Task 6.

**Placeholder scan:** No TBD/TODO. Every code step contains complete code. The
one judgment call (single-target error unwrapping in Task 4 Step 5) states both
options and a recommendation rather than deferring.

**Type consistency:** `DisplayInfo` fields are identical across Tasks 2, 4, 6.
`Target` cases (`main`/`all`/`selector`) match between Tasks 4 and 7.
`BrightnessBackend` signatures match between Tasks 4 (protocol), 4 (fake), and
6 (real). `Percent` method names match across Tasks 1, 4, 5. `MBrightError`
cases used in Tasks 4 and 6 are all declared in Task 3.
