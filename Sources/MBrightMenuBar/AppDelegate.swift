import AppKit
import MBrightIPC

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuController: StatusMenuController?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        menuController = StatusMenuController(connection: DaemonConnection())
    }
}
