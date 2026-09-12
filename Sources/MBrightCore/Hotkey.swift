import CoreGraphics
import Foundation

/// One keyboard shortcut as written in the config: modifiers and one key
/// joined by `+`, such as `lopt+f1`. Parsed once; the wire and the file
/// carry the canonical string.
public struct KeyCombination: Equatable, Sendable, CustomStringConvertible {
    public enum Modifier: String, CaseIterable, Sendable {
        // Canonical order, the one macOS uses to draw shortcuts: ⌃⌥⇧⌘.
        case control = "ctrl"
        case option = "opt"
        case shift = "shift"
        case command = "cmd"

        var flag: CGEventFlags {
            switch self {
            case .control: return .maskControl
            case .option: return .maskAlternate
            case .shift: return .maskShift
            case .command: return .maskCommand
            }
        }

        /// Device-side bits from IOKit's IOLLEvent.h. CoreGraphics sets
        /// them on real key presses alongside the plain modifier flag.
        func deviceBit(_ side: Side) -> CGEventFlags {
            switch (self, side) {
            case (.control, .left): return CGEventFlags(rawValue: 0x0000_0001)
            case (.control, .right): return CGEventFlags(rawValue: 0x0000_2000)
            case (.shift, .left): return CGEventFlags(rawValue: 0x0000_0002)
            case (.shift, .right): return CGEventFlags(rawValue: 0x0000_0004)
            case (.command, .left): return CGEventFlags(rawValue: 0x0000_0008)
            case (.command, .right): return CGEventFlags(rawValue: 0x0000_0010)
            case (.option, .left): return CGEventFlags(rawValue: 0x0000_0020)
            case (.option, .right): return CGEventFlags(rawValue: 0x0000_0040)
            }
        }
    }

    public enum Side: String, Sendable {
        case left = "l"
        case right = "r"
    }

    /// One required modifier; `side == nil` accepts either key.
    public struct Requirement: Equatable, Sendable {
        public let modifier: Modifier
        public let side: Side?

        public init(_ modifier: Modifier, side: Side? = nil) {
            self.modifier = modifier
            self.side = side
        }

        var token: String { (side?.rawValue ?? "") + modifier.rawValue }
    }

    /// In canonical order, one entry per modifier.
    public let modifiers: [Requirement]
    /// US-layout virtual key code, as `CGEvent`'s `keyboardEventKeycode`.
    public let keyCode: UInt16
    public let keyName: String

    public init(parsing text: String) throws {
        let parts = text.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func fail(_ reason: String) -> MBrightError { .invalidHotkey(keys: text, reason: reason) }
        guard parts != [""] else { throw fail("no key named; expected something like 'lopt+f1'") }

        var found: [Modifier: Side?] = [:]
        var key: (name: String, code: UInt16)?
        for part in parts {
            if part.isEmpty {
                throw fail("empty part; separate modifiers and the key with '+'")
            }
            if let requirement = Self.modifier(named: part) {
                guard found[requirement.modifier] == nil else {
                    throw fail("'\(requirement.modifier.rawValue)' is listed twice")
                }
                found[requirement.modifier] = requirement.side
            } else if let code = Self.keyCodes[part] {
                guard key == nil else { throw fail("more than one key; use one key with any modifiers") }
                key = (part, code)
            } else {
                throw fail("unknown key '\(part)'")
            }
        }
        guard let key else { throw fail("no key named; expected something like 'lopt+f1'") }
        if found.isEmpty, !Self.functionKeys.contains(key.name) {
            throw fail("needs at least one modifier")
        }
        modifiers = Modifier.allCases.compactMap { modifier in
            found[modifier].map { Requirement(modifier, side: $0) }
        }
        keyCode = key.code
        keyName = key.name
    }

    /// The canonical spelling: `ctrl`, `opt`, `shift`, `cmd` in that order,
    /// each with its side prefix, then the key.
    public var description: String {
        (modifiers.map(\.token) + [keyName]).joined(separator: "+")
    }

    /// Whether a key-down with this key code and these flags is this
    /// shortcut. The four modifiers must match exactly; a sided one also
    /// needs its device bit, an unsided one takes either side. Fn, Caps
    /// Lock, the numeric-pad and the coalescing flag are ignored.
    public func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard keyCode == Int64(self.keyCode) else { return false }
        for modifier in Modifier.allCases {
            let requirement = modifiers.first { $0.modifier == modifier }
            guard flags.contains(modifier.flag) == (requirement != nil) else { return false }
            if let side = requirement?.side, !flags.contains(modifier.deviceBit(side)) {
                return false
            }
        }
        return true
    }

    // MARK: - Tables

    private static func modifier(named token: String) -> Requirement? {
        if let modifier = modifierNames[token] { return Requirement(modifier) }
        for (prefix, side) in [("left-", Side.left), ("right-", .right), ("l", .left), ("r", .right)]
        where token.hasPrefix(prefix) {
            if let modifier = modifierNames[String(token.dropFirst(prefix.count))] {
                return Requirement(modifier, side: side)
            }
        }
        return nil
    }

    private static let modifierNames: [String: Modifier] = [
        "cmd": .command, "command": .command,
        "ctrl": .control, "control": .control,
        "opt": .option, "option": .option, "alt": .option,
        "shift": .shift,
    ]

    private static let functionKeys: Set<String> = Set((1...20).map { "f\($0)" })

    /// Virtual key codes from Carbon's `Events.h`, US layout.
    private static let keyCodes: [String: UInt16] = [
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61, "f7": 0x62,
        "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F, "f13": 0x69, "f14": 0x6B,
        "f15": 0x71, "f16": 0x6A, "f17": 0x40, "f18": 0x4F, "f19": 0x50, "f20": 0x5A,
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28,
        "n": 0x2D, "m": 0x2E,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19, "7": 0x1A,
        "8": 0x1C, "0": 0x1D,
        "=": 0x18, "-": 0x1B, "]": 0x1E, "[": 0x21, "'": 0x27, ";": 0x29, "\\": 0x2A, ",": 0x2B,
        "/": 0x2C, ".": 0x2F, "`": 0x32,
        "return": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33, "escape": 0x35,
        "home": 0x73, "pageup": 0x74, "forwarddelete": 0x75, "end": 0x77, "pagedown": 0x79,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
    ]
}

extension KeyCombination: Codable {
    public init(from decoder: Decoder) throws {
        try self.init(parsing: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// One entry of the config's `hotkeys` list: which keys adjust which
/// display by how much.
public struct Hotkey: Equatable, Sendable, CustomStringConvertible {
    public enum Action: String, Codable, Sendable {
        case up
        case down
    }

    public static let defaultStep = 5
    /// The step of the default Shift variants.
    public static let largeStep = 20

    /// The issue's proposal: Left Option + F1/F2 for the main display,
    /// Right Option + F1/F2 for the second one; the same with Shift held
    /// moves in larger steps.
    public static let defaults: [Hotkey] = [
        Hotkey(keys: "lopt+f1", action: .down, display: .main),
        Hotkey(keys: "lopt+f2", action: .up, display: .main),
        Hotkey(keys: "ropt+f1", action: .down, display: .secondary),
        Hotkey(keys: "ropt+f2", action: .up, display: .secondary),
        Hotkey(keys: "lopt+shift+f1", action: .down, display: .main, step: largeStep),
        Hotkey(keys: "lopt+shift+f2", action: .up, display: .main, step: largeStep),
        Hotkey(keys: "ropt+shift+f1", action: .down, display: .secondary, step: largeStep),
        Hotkey(keys: "ropt+shift+f2", action: .up, display: .secondary, step: largeStep),
    ]

    public var keys: KeyCombination
    public var action: Action
    public var display: Target
    /// Percentage points per press, 1 to 100.
    public var step: Int

    public init(keys: KeyCombination, action: Action, display: Target = .main, step: Int = defaultStep) {
        self.keys = keys
        self.action = action
        self.display = display
        self.step = step
    }

    /// For literals that are known to parse.
    private init(keys: String, action: Action, display: Target, step: Int = defaultStep) {
        self.init(keys: try! KeyCombination(parsing: keys), action: action, display: display, step: step)
    }

    public var delta: Int { action == .up ? step : -step }

    /// `lopt+f1  main down 5`, the form `config show` prints.
    public var description: String {
        "\(keys)  \(Self.displayName(display)) \(action.rawValue) \(step)"
    }

    static func displayName(_ target: Target) -> String {
        switch target {
        case .main: return "main"
        case .secondary: return "secondary"
        case .all: return "all"
        case let .selector(selector): return selector
        case let .id(id): return "\(id)"
        }
    }

    static func target(named name: String) -> Target {
        switch name {
        case "main": return .main
        case "secondary": return .secondary
        case "all": return .all
        default: return .selector(name)
        }
    }
}

extension Hotkey: Codable {
    private enum CodingKeys: String, CodingKey { case keys, action, display, step }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keys = try container.decode(KeyCombination.self, forKey: .keys)
        action = try container.decode(Action.self, forKey: .action)
        display = Self.target(named: try container.decodeIfPresent(String.self, forKey: .display) ?? "main")
        step = try container.decodeIfPresent(Int.self, forKey: .step) ?? Self.defaultStep
        guard (1...100).contains(step) else {
            throw MBrightError.invalidHotkey(keys: keys.description, reason: "step must be between 1 and 100")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keys, forKey: .keys)
        try container.encode(action, forKey: .action)
        try container.encode(Self.displayName(display), forKey: .display)
        try container.encode(step, forKey: .step)
    }
}
