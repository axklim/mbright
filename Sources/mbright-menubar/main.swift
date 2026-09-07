import AppKit
import MBrightMenuBar

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Accessory: lives in the menu bar only, no Dock icon, no main window.
app.setActivationPolicy(.accessory)
app.run()
