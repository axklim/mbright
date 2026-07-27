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
