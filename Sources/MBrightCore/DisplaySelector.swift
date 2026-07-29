import CoreGraphics

/// Resolves a user-supplied `--display` selector to exactly one display.
///
/// Precedence is strict, not best-match: list index, then CGDirectDisplayID,
/// then case-insensitive name substring. Indices and display IDs share a
/// numeric namespace and do collide in practice, so ordering is what makes a
/// numeric selector unambiguous.
public enum DisplaySelector {
    public static func resolve(_ selector: String, in displays: [DisplayInfo]) throws -> DisplayInfo {
        if let number = Int(selector) {
            if let byIndex = displays.first(where: { $0.index == number }) {
                return byIndex
            }
            // UInt32(exactly:) rather than UInt32(_:) — the latter traps on
            // negative or oversized input.
            if let id = UInt32(exactly: number),
               let byID = displays.first(where: { $0.id == id }) {
                return byID
            }
        }

        let needle = selector.lowercased()
        let matches = displays.filter { $0.name.lowercased().contains(needle) }

        switch matches.count {
        case 1:
            return matches[0]
        case 0:
            throw MBrightError.noMatch(selector: selector, available: displays.map(\.name))
        default:
            throw MBrightError.ambiguousSelector(selector: selector, candidates: matches.map(\.name))
        }
    }
}
