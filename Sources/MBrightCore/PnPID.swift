/// Decodes an EDID PnP vendor ID as packed by `CGDisplayVendorNumber`:
/// three 5-bit letters, A == 1, most significant first.
public enum PnPID {
    public static func decode(_ raw: UInt32) -> String {
        guard raw > 0, raw <= 0xFFFF else { return "?" }

        let groups = [(raw >> 10) & 0x1F, (raw >> 5) & 0x1F, raw & 0x1F]
        guard groups.allSatisfy({ (1...26).contains($0) }) else { return "?" }

        return String(groups.map { Character(UnicodeScalar(UInt8($0) + 64)) })
    }
}
