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

@Test func getMainSelectsIsMainDisplayNotArrayPosition() throws {
    // studio (isMain: true) is second in the array here, so a naive
    // "first element" implementation would return ultrafine's value instead.
    let backend = FakeBackend(values: [3: 0.37, 2: 0.49])
    let (sut, _) = controller(FakeEnumerator([ultrafine, studio]), backend)
    #expect(try sut.get(.main) == 37)
}

@Test func getMainFallsBackToFirstDisplayWhenNoneIsMain() throws {
    let first = DisplayInfo(index: 0, id: 10, name: "Display A", vendor: "APP", isMain: false)
    let second = DisplayInfo(index: 1, id: 20, name: "Display B", vendor: "APP", isMain: false)
    let backend = FakeBackend(values: [10: 0.42, 20: 0.77])
    let (sut, _) = controller(FakeEnumerator([first, second]), backend)
    #expect(try sut.get(.main) == 42)
}

@Test func getAllThrowsBecauseGetReportsOnlyOneDisplay() {
    let (sut, _) = controller()
    #expect(throws: MBrightError.getDoesNotSupportAll) {
        try sut.get(.all)
    }
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
    #expect(throws: MBrightError.self) {
        try sut.set(percent: 50, target: .selector("studio"))
    }
}

@Test func getOnUnsupportedDisplayThrows() {
    // An unsupported main display is a realistic configuration -- get()
    // hits ensureSupported directly, not through apply()'s per-display
    // catch, so this path needs its own coverage.
    let backend = FakeBackend()
    backend.unsupported = [3]
    let (sut, _) = controller(FakeEnumerator(), backend)
    #expect(throws: MBrightError.brightnessUnsupported(display: "Studio Display")) {
        try sut.get(.main)
    }
}

@Test func allContinuesPastFailureThenThrows() {
    let backend = FakeBackend()
    backend.failing = [3]
    let (sut, _) = controller(FakeEnumerator(), backend)

    // Tightened to the specific .partialFailure case: asserting only
    // `MBrightError.self` would still pass if apply() rethrew the last
    // per-display error instead of aggregating, which would silently
    // break the spec-mandated "one failure doesn't abort the others"
    // contract.
    do {
        try sut.set(percent: 30, target: .all)
        Issue.record("Expected MBrightError.partialFailure to be thrown")
    } catch let error as MBrightError {
        guard case .partialFailure = error else {
            Issue.record("Expected .partialFailure, got \(error)")
            return
        }
    } catch {
        Issue.record("Expected MBrightError, got \(error)")
    }
    // The healthy display must still have been written.
    #expect(backend.values[2] == 0.3)
}

@Test func readingsDistinguishUnsupportedFromFailed() throws {
    // Three displays, three outcomes: a healthy read, a display that
    // reports no brightness control, and a display whose read throws.
    // Collapsing "unsupported" and "read failed" into the same nil-like
    // state would hide a real I/O failure behind a benign capability report.
    let thirdDisplay = DisplayInfo(index: 2, id: 99, name: "Third Display", vendor: "APP", isMain: false)
    let backend = FakeBackend(values: [3: 0.4, 2: 0.6, 99: 0.5])
    backend.unsupported = [2]
    backend.failing = [99]
    let (sut, _) = controller(FakeEnumerator([studio, ultrafine, thirdDisplay]), backend)

    let readings = try sut.readings()
    #expect(readings.count == 3)
    #expect(readings[0].state == .percent(40))
    #expect(readings[1].state == .unsupported)
    #expect(readings[2].state == .failed("Brightness operation failed on display 99 (code -1)"))
}

@Test func emptyDisplayListThrows() {
    let (sut, _) = controller(FakeEnumerator([]), FakeBackend())
    #expect(throws: MBrightError.noDisplays) { try sut.get(.main) }
}

@Test func readingsThrowsOnEmptyDisplayList() {
    // readings() reached the backend via a different path than
    // get/set/adjust (all three go through resolve(), which already
    // guards this) and used to print a blank line and exit 0 instead.
    let (sut, _) = controller(FakeEnumerator([]), FakeBackend())
    #expect(throws: MBrightError.noDisplays) { try sut.readings() }
}
