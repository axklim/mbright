import Testing
@testable import MBrightCore

@Test func rendersAlignedTable() {
    let output = ListTable.render([
        DisplayReading(display: studio, state: .percent(37)),
        DisplayReading(display: ultrafine, state: .percent(49)),
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
    let output = ListTable.render([DisplayReading(display: studio, state: .percent(37))])
    #expect(output.contains("*"))
}

@Test func rendersUnsupportedAsDash() {
    let output = ListTable.render([DisplayReading(display: ultrafine, state: .unsupported)])
    #expect(output.contains("-"))
    #expect(!output.contains("%"))
}

@Test func rendersFailedAsError() {
    let output = ListTable.render([
        DisplayReading(display: ultrafine, state: .failed("Brightness operation failed on '3' (code -1)")),
    ])
    #expect(output.contains("ERROR"))
    #expect(!output.contains("-"))
    #expect(!output.contains("%"))
}

@Test func handlesEmptyInput() {
    #expect(ListTable.render([]) == "")
}

@Test func neverTruncatesMultiCodeUnitGraphemes() {
    // A family emoji is one grapheme cluster (String.count == 1) but many
    // UTF-16 code units. Padding that measures width in grapheme clusters
    // and then pads via UTF-16 length (NSString.padding(toLength:)) chops
    // it mid-sequence. Display names come from NSScreen.localizedName and
    // are not guaranteed ASCII, so this must never truncate.
    let familyEmojiName = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
    let display = DisplayInfo(index: 3, id: 7, name: familyEmojiName, vendor: "APP", isMain: false)
    let output = ListTable.render([DisplayReading(display: display, state: .percent(50))])
    #expect(output.contains(familyEmojiName))
}
