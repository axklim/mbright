import Testing
@testable import MBrightCore

// Target.resolve is the whole mutual-exclusion policy for --display/--all.
// It has to live in MBrightCore to be testable at all: TargetOptions in the
// mbright executable target has no test target exercising it.

@Test func resolveRejectsDisplayAndAllTogether() {
    #expect(throws: MBrightError.conflictingTargetFlags) {
        try Target.resolve(display: "studio", all: true)
    }
}

@Test func resolveAllAloneReturnsAll() throws {
    #expect(try Target.resolve(display: nil, all: true) == .all)
}

@Test func resolveDisplayAloneReturnsSelector() throws {
    #expect(try Target.resolve(display: "studio", all: false) == .selector("studio"))
}

@Test func resolveNeitherReturnsMain() throws {
    #expect(try Target.resolve(display: nil, all: false) == .main)
}
