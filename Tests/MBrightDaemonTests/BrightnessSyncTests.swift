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
