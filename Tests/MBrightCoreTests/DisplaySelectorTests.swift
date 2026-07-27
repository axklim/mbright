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
