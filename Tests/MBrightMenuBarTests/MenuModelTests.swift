import Testing
@testable import MBrightCore
@testable import MBrightMenuBar

private let studio = DisplayInfo(index: 0, id: 3, name: "Studio Display", vendor: "APP", isMain: true)
private let ultrafine = DisplayInfo(index: 1, id: 2, name: "LG UltraFine", vendor: "GSM", isMain: false)

@Test func rowsKeepOrderAndMapEveryState() {
    let rows = MenuModel.rows(from: [
        DisplayReading(display: studio, state: .percent(79)),
        DisplayReading(display: ultrafine, state: .unsupported),
        DisplayReading(display: ultrafine, state: .failed("code -1")),
    ])
    #expect(rows == [
        DisplayRow(id: 3, name: "Studio Display", percent: 79, detail: nil),
        DisplayRow(id: 2, name: "LG UltraFine", percent: nil, detail: "No brightness control"),
        DisplayRow(id: 2, name: "LG UltraFine", percent: nil, detail: "Error: code -1"),
    ])
}
