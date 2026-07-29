import Testing
@testable import MBrightCore

// DisplayServices is private API with no documented contract. This guard is
// the only branch standing between a malformed "success" response and an
// uncatchable trap in Percent.fromDevice, so it is the highest-value logic
// in DisplayServicesBackend -- extracted here so it can actually be tested.

@Test func rejectsNaN() {
    #expect(DeviceValue.validated(Float.nan) == nil)
}

@Test func rejectsPositiveInfinity() {
    #expect(DeviceValue.validated(Float.infinity) == nil)
}

@Test func rejectsNegativeInfinity() {
    #expect(DeviceValue.validated(-Float.infinity) == nil)
}

@Test func rejectsTheMinusOneSentinel() {
    // The value DisplayServicesBackend's out-param starts at, so a
    // call that never writes it must still fail validation.
    #expect(DeviceValue.validated(-1) == nil)
}

@Test func rejectsAboveUnitRange() {
    #expect(DeviceValue.validated(1.5) == nil)
}

@Test func acceptsLowerBoundZero() {
    #expect(DeviceValue.validated(0.0) == 0.0)
}

@Test func acceptsUpperBoundOne() {
    #expect(DeviceValue.validated(1.0) == 1.0)
}
