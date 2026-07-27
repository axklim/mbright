/// Renders `list` output as a column-aligned table.
public enum ListTable {
    public static func render(_ readings: [DisplayReading]) -> String {
        guard !readings.isEmpty else { return "" }

        let header = ["INDEX", "NAME", "VENDOR", "ID", "BRIGHTNESS"]
        let rows = readings.map { reading in
            [
                "\(reading.display.index)" + (reading.display.isMain ? "*" : ""),
                reading.display.name,
                reading.display.vendor,
                "\(reading.display.id)",
                cell(for: reading.state),
            ]
        }

        let allRows = [header] + rows
        let lastColumn = header.count - 1
        let widths = (0..<header.count).map { column in
            allRows.map { $0[column].count }.max() ?? 0
        }

        let lines: [String] = allRows.map { row in renderLine(row, widths: widths, lastColumn: lastColumn) }
        return lines.joined(separator: "\n")
    }

    private static func renderLine(_ row: [String], widths: [Int], lastColumn: Int) -> String {
        var line = ""
        for (column, value) in row.enumerated() {
            line += pad(value, to: widths[column], isLast: column == lastColumn)
        }
        return line
    }

    /// Pads `cell` with spaces up to `width + 2`, measuring and padding in
    /// grapheme clusters throughout so multi-code-unit characters (combining
    /// marks, most emoji) are never truncated.
    private static func pad(_ cell: String, to width: Int, isLast: Bool) -> String {
        guard !isLast else { return cell }
        let deficit = max(0, width + 2 - cell.count)
        return cell + String(repeating: " ", count: deficit)
    }

    private static func cell(for state: BrightnessState) -> String {
        switch state {
        case .percent(let value): return "\(value)%"
        case .unsupported: return "-"
        case .failed: return "ERROR"
        }
    }
}
