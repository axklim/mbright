import Testing
@testable import MBrightCore
@testable import MBrightIPC

@Test func readingsReturnEveryDisplay() {
    let backend = FakeBackend(values: [3: 0.79, 2: 0.46])
    let response = makeHandler(FakeEnumerator(), backend).handle(.readings)
    #expect(response == .readings([
        DisplayReading(display: studio, state: .percent(79)),
        DisplayReading(display: ultrafine, state: .percent(46)),
    ]))
}

@Test func getReturnsPercentForTarget() {
    let backend = FakeBackend(values: [3: 0.79, 2: 0.46])
    let handler = makeHandler(FakeEnumerator(), backend)
    #expect(handler.handle(.get(target: .main)) == .percent(79))
    #expect(handler.handle(.get(target: .selector("ultra"))) == .percent(46))
    #expect(handler.handle(.get(target: .id(2))) == .percent(46))
}

@Test func setWritesAndAcknowledges() {
    let backend = FakeBackend()
    let handler = makeHandler(FakeEnumerator(), backend)
    #expect(handler.handle(.set(percent: 25, target: .id(2))) == .ok)
    #expect(backend.writes.count == 1)
    #expect(backend.writes[0].id == 2)
    #expect(backend.writes[0].value == 0.25)
}

@Test func adjustClampsAndAcknowledges() {
    let backend = FakeBackend(values: [3: 0.95, 2: 0.5])
    let handler = makeHandler(FakeEnumerator(), backend)
    #expect(handler.handle(.adjust(delta: 10, target: .main)) == .ok)
    #expect(backend.values[3] == 1.0)
}

@Test func controllerErrorsBecomeTypedFailures() {
    let handler = makeHandler(FakeEnumerator(), FakeBackend())
    #expect(handler.handle(.get(target: .all)) == .failure(.getDoesNotSupportAll))
    #expect(handler.handle(.get(target: .selector("nope")))
        == .failure(.noMatch(selector: "nope", available: ["Studio Display", "LG UltraFine"])))
    #expect(handler.handle(.get(target: .id(99)))
        == .failure(.noMatch(selector: "99", available: ["Studio Display", "LG UltraFine"])))
}

@Test func noDisplaysIsReportedNotSwallowed() {
    let handler = makeHandler(FakeEnumerator([]), FakeBackend())
    #expect(handler.handle(.readings) == .failure(.noDisplays))
}

@Test func versionAndSubscribeAnswerWithoutTouchingHardware() {
    let backend = FakeBackend()
    let handler = makeHandler(FakeEnumerator([]), backend)
    #expect(handler.handle(.version) == .version("9.9.9"))
    #expect(handler.handle(.subscribe) == .ok)
    // Exiting is the daemon executable's job; the handler only acknowledges.
    #expect(handler.handle(.shutdown) == .ok)
    #expect(backend.writes.isEmpty)
}
