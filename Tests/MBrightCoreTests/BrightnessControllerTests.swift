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
    #expect(throws: MBrightError.self) {
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
