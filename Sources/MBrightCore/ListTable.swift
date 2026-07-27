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

        let widths = (0..<header.count).map { column in
            ([header] + rows).map { $0[column].count }.max() ?? 0
        }

        return ([header] + rows)
            .map { row in
                row.enumerated()
                    .map { $0.offset == row.count - 1
                        ? $0.element
                        : $0.element.padding(toLength: widths[$0.offset] + 2, withPad: " ", startingAt: 0) }
                    .joined()
            }
            .joined(separator: "\n")
    }

    private static func cell(for state: BrightnessState) -> String {
        switch state {
        case .percent(let value): return "\(value)%"
        case .unsupported: return "-"
        case .failed: return "ERROR"
        }
    }
}
