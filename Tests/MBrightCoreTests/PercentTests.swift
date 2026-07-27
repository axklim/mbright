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
