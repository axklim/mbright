import AppKit
import CoreGraphics

/// Online displays from CoreGraphics, with friendly names from AppKit.
/// `NSScreen.localizedName` works from a plain CLI with no NSApplication;
/// this was verified on the target machine.
public struct SystemDisplayEnumerator: DisplayEnumerating {
    private static let maxDisplays = 16

    public init() {}

    public func onlineDisplays() throws -> [DisplayInfo] {
        var ids = [CGDirectDisplayID](repeating: 0, count: Self.maxDisplays)
        var count: UInt32 = 0

        let error = CGGetOnlineDisplayList(UInt32(Self.maxDisplays), &ids, &count)
        guard error == .success else {
            throw MBrightError.enumerationFailed(code: error.rawValue)
        }

        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            names[CGDirectDisplayID(number.uint32Value)] = screen.localizedName
        }

        return (0..<Int(count)).map { index in
            let id = ids[index]
            return DisplayInfo(
                index: index,
                id: id,
                name: names[id] ?? "Display \(id)",
                vendor: PnPID.decode(CGDisplayVendorNumber(id)),
                isMain: CGDisplayIsMain(id) != 0
            )
        }
    }
}
