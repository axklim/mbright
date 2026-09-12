import AppKit
import ApplicationServices
import CoreGraphics
import MBrightCore

/// Global keyboard shortcuts through a session event tap. The tap sees
/// the device-side modifier bits (left Option is not right Option) and
/// swallows a matched key so the system does not act on it too, which
/// Carbon's hot keys can do neither of. The price is Accessibility
/// access: without it the tap cannot be created, the app asks once with
/// the system prompt, and keeps trying every few seconds until granted.
@MainActor
final class HotkeyListener {
    enum State: Equatable {
        /// No shortcuts configured.
        case off
        case listening
        /// Shortcuts configured but the tap could not be created.
        case needsAccessibility
    }

    static let retryInterval: TimeInterval = 3

    private(set) var state: State = .off {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((State) -> Void)?
    var onHotkey: ((Hotkey) -> Void)?

    private var hotkeys: [Hotkey] = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retry: Timer?
    private var prompted = false
    private let log: (String) -> Void

    init(log: @escaping (String) -> Void) {
        self.log = log
    }

    /// Replaces the shortcut list. The tap stays up across changes; it is
    /// only removed when the list empties.
    func update(_ hotkeys: [Hotkey]) {
        self.hotkeys = hotkeys
        log("hotkeys: \(hotkeys.isEmpty ? "off" : hotkeys.map(\.description).joined(separator: "; "))")
        guard !hotkeys.isEmpty else {
            removeTap()
            state = .off
            return
        }
        guard tap == nil else { return }
        install()
    }

    static func openAccessibilitySettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }

    // MARK: - Tap

    private func install() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: hotkeyTapCallback, userInfo: info)
        else {
            log("hotkeys: event tap refused, trusted \(AXIsProcessTrusted())")
            state = .needsAccessibility
            if !prompted {
                prompted = true
                // kAXTrustedCheckOptionPrompt is a mutable C global, which
                // strict concurrency refuses; its value is this string.
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            scheduleRetry()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        retry?.invalidate()
        retry = nil
        log("hotkeys: event tap installed")
        state = .listening
    }

    private func removeTap() {
        retry?.invalidate()
        retry = nil
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
        log("hotkeys: event tap removed")
    }

    private func scheduleRetry() {
        guard retry == nil else { return }
        retry = Timer.scheduledTimer(withTimeInterval: Self.retryInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.tap == nil, !self.hotkeys.isEmpty else { return }
                self.install()
            }
        }
    }

    /// Runs on the main run loop, where the tap's source lives. Returns
    /// whether the event was a shortcut and is to be consumed.
    fileprivate func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system switches a tap off when its callback is slow or
            // during secure input; switching it back on is all it wants.
            log("hotkeys: tap disabled (\(type.rawValue)), re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .keyDown:
            guard let hotkey = hotkeys.first(where: { $0.keys.matches(keyCode: keyCode, flags: flags) }) else {
                return false
            }
            log("hotkeys: \(hotkey.keys) (keycode \(keyCode), flags 0x\(String(flags.rawValue, radix: 16)))")
            onHotkey?(hotkey)
            return true
        default:
            return false
        }
    }
}

/// A C function pointer cannot capture, so the listener travels in
/// `userInfo`. `nil` consumes the event.
private let hotkeyTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let listener = Unmanaged<HotkeyListener>.fromOpaque(userInfo).takeUnretainedValue()
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    let consumed = MainActor.assumeIsolated { listener.handle(type: type, keyCode: keyCode, flags: flags) }
    return consumed ? nil : Unmanaged.passUnretained(event)
}
