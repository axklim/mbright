import CoreGraphics

/// One online display, as presented to the user.
public struct DisplayInfo: Equatable, Sendable, Codable {
    /// Position in `list` output. Not stable across replugs.
    public let index: Int
    public let id: CGDirectDisplayID
    public let name: String
    /// EDID PnP vendor code, e.g. "APP" or "GSM".
    public let vendor: String
    public let isMain: Bool

    public init(index: Int, id: CGDirectDisplayID, name: String, vendor: String, isMain: Bool) {
        self.index = index
        self.id = id
        self.name = name
        self.vendor = vendor
        self.isMain = isMain
    }
}
