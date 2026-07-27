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
