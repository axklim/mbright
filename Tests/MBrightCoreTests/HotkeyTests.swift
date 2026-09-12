import CoreGraphics
import Foundation
import Testing
@testable import MBrightCore

// Device-side modifier bits from IOKit's IOLLEvent.h, as they appear in
// CGEventFlags on a real key press.
private let leftOption = CGEventFlags(rawValue: 0x20)
private let rightOption = CGEventFlags(rawValue: 0x40)
private let leftCommand = CGEventFlags(rawValue: 0x08)
private let rightCommand = CGEventFlags(rawValue: 0x10)
private let leftShift = CGEventFlags(rawValue: 0x02)
private let leftControl = CGEventFlags(rawValue: 0x01)
private let rightControl = CGEventFlags(rawValue: 0x2000)

private func flags(_ parts: CGEventFlags...) -> CGEventFlags {
    parts.reduce(CGEventFlags()) { $0.union($1) }
}

private func parse(_ keys: String) throws -> KeyCombination {
    try KeyCombination(parsing: keys)
}

// MARK: - Parsing

@Test func keyCombinationParsesModifiersAndKey() throws {
    let combination = try parse("lopt+f1")
    #expect(combination.keyCode == 0x7A)
    #expect(combination.modifiers == [.init(.option, side: .left)])
    #expect(combination.description == "lopt+f1")
}

@Test func keyCombinationIsCaseInsensitiveAndAcceptsAliases() throws {
    #expect(try parse("Left-Option+F2").description == "lopt+f2")
    #expect(try parse("ALT+f2").description == "opt+f2")
    #expect(try parse("Command+Control+Shift+Option+A").description == "ctrl+opt+shift+cmd+a")
    #expect(try parse("ralt+f1") == parse("right-option+f1"))
    #expect(try parse(" cmd + f3 ").description == "cmd+f3")
}

@Test func keyCombinationCanonicalOrderIsControlOptionShiftCommand() throws {
    #expect(try parse("cmd+shift+opt+ctrl+f5").description == "ctrl+opt+shift+cmd+f5")
    #expect(try parse("rcmd+lshift+f5").description == "lshift+rcmd+f5")
}

@Test func keyCombinationKnowsEveryDocumentedKey() throws {
    #expect(try parse("cmd+f20").keyCode == 0x5A)
    #expect(try parse("cmd+a").keyCode == 0x00)
    #expect(try parse("cmd+0").keyCode == 0x1D)
    #expect(try parse("cmd+up").keyCode == 0x7E)
    #expect(try parse("cmd+space").keyCode == 0x31)
    #expect(try parse("cmd+return").keyCode == 0x24)
    #expect(try parse("cmd+escape").keyCode == 0x35)
    #expect(try parse("cmd+delete").keyCode == 0x33)
    #expect(try parse("cmd+forwarddelete").keyCode == 0x75)
    #expect(try parse("cmd+pagedown").keyCode == 0x79)
    #expect(try parse("cmd+-").keyCode == 0x1B)
    #expect(try parse("cmd+=").keyCode == 0x18)
    #expect(try parse("cmd+`").keyCode == 0x32)
    #expect(try parse("cmd+\\").keyCode == 0x2A)
    #expect(try parse("cmd+'").keyCode == 0x27)
}

@Test func keyCombinationRejectsMalformedInput() {
    let cases: [(String, String)] = [
        ("", "no key named"),
        ("lopt", "no key named"),
        ("lopt+f1+f2", "more than one key"),
        ("lopt+f99", "unknown key 'f99'"),
        ("lopt+ropt+f1", "'opt' is listed twice"),
        ("a", "needs at least one modifier"),
        ("lopt++f1", "empty part"),
    ]
    for (keys, reason) in cases {
        #expect(throws: MBrightError.self, "\(keys)") { try parse(keys) }
        do {
            _ = try parse(keys)
        } catch let error as MBrightError {
            guard case let .invalidHotkey(actual, actualReason) = error else {
                Issue.record("\(keys): unexpected error \(error)")
                continue
            }
            #expect(actual == keys)
            #expect(actualReason.contains(reason), "\(keys): \(actualReason)")
        } catch {
            Issue.record("\(keys): unexpected error \(error)")
        }
    }
}

@Test func functionKeysNeedNoModifier() throws {
    #expect(try parse("f13").modifiers.isEmpty)
    #expect(try parse("F13").description == "f13")
}

@Test func keyCombinationCodesAsItsCanonicalString() throws {
    let data = try JSONEncoder().encode([try parse("Right-Option+F2")])
    #expect(String(decoding: data, as: UTF8.self) == #"["ropt+f2"]"#)
    let decoded = try JSONDecoder().decode([KeyCombination].self, from: Data(#"["lopt+f1"]"#.utf8))
    #expect(decoded == [try parse("lopt+f1")])
}

@Test func keyCombinationDecodeSurfacesTheParseError() {
    #expect(throws: MBrightError.invalidHotkey(keys: "lopt+f99", reason: "unknown key 'f99'")) {
        try JSONDecoder().decode([KeyCombination].self, from: Data(#"["lopt+f99"]"#.utf8))
    }
}

// MARK: - Matching

@Test func sidedModifierMatchesOnlyThatSide() throws {
    let left = try parse("lopt+f1")
    let right = try parse("ropt+f1")
    let leftPress = flags(.maskAlternate, leftOption)
    let rightPress = flags(.maskAlternate, rightOption)
    #expect(left.matches(keyCode: 0x7A, flags: leftPress))
    #expect(!left.matches(keyCode: 0x7A, flags: rightPress))
    #expect(right.matches(keyCode: 0x7A, flags: rightPress))
    #expect(!right.matches(keyCode: 0x7A, flags: leftPress))
    // Both Option keys held: each side's bit is set, so both bindings match.
    #expect(left.matches(keyCode: 0x7A, flags: flags(.maskAlternate, leftOption, rightOption)))
}

@Test func sidedModifierNeedsTheDeviceBitNotJustTheModifier() throws {
    // A synthetic event, or a keyboard that reports no side, sets the
    // modifier without a device bit; that must not match a sided binding.
    let left = try parse("lopt+f1")
    #expect(!left.matches(keyCode: 0x7A, flags: .maskAlternate))
    #expect(try parse("opt+f1").matches(keyCode: 0x7A, flags: .maskAlternate))
}

@Test func unsidedModifierMatchesEitherSide() throws {
    let any = try parse("opt+f1")
    #expect(any.matches(keyCode: 0x7A, flags: flags(.maskAlternate, leftOption)))
    #expect(any.matches(keyCode: 0x7A, flags: flags(.maskAlternate, rightOption)))
}

@Test func modifierSetMustMatchExactly() throws {
    let binding = try parse("lopt+f1")
    #expect(!binding.matches(keyCode: 0x7A, flags: flags(.maskAlternate, leftOption, .maskShift, leftShift)))
    #expect(!binding.matches(keyCode: 0x7A, flags: flags(.maskAlternate, leftOption, .maskCommand, leftCommand)))
    #expect(!binding.matches(keyCode: 0x7A, flags: CGEventFlags()))
    let two = try parse("ctrl+cmd+f1")
    #expect(two.matches(keyCode: 0x7A, flags: flags(.maskControl, rightControl, .maskCommand, rightCommand)))
    #expect(!two.matches(keyCode: 0x7A, flags: flags(.maskControl, leftControl)))
}

@Test func fnCapsLockAndNumericPadFlagsAreIgnored() throws {
    let binding = try parse("lopt+f1")
    let noise = flags(.maskSecondaryFn, .maskAlphaShift, .maskNumericPad, .maskNonCoalesced)
    #expect(binding.matches(keyCode: 0x7A, flags: flags(.maskAlternate, leftOption, noise)))
    #expect(try parse("f13").matches(keyCode: 0x69, flags: noise))
}

@Test func keyCodeMustMatch() throws {
    let binding = try parse("lopt+f1")
    #expect(!binding.matches(keyCode: 0x78, flags: flags(.maskAlternate, leftOption)))
}

// MARK: - Hotkey

@Test func hotkeyDefaultsAreTheIssueProposalPlusShiftForLargeSteps() throws {
    #expect(Hotkey.defaults == [
        Hotkey(keys: try parse("lopt+f1"), action: .down, display: .main, step: 5),
        Hotkey(keys: try parse("lopt+f2"), action: .up, display: .main, step: 5),
        Hotkey(keys: try parse("ropt+f1"), action: .down, display: .secondary, step: 5),
        Hotkey(keys: try parse("ropt+f2"), action: .up, display: .secondary, step: 5),
        Hotkey(keys: try parse("lopt+shift+f1"), action: .down, display: .main, step: 20),
        Hotkey(keys: try parse("lopt+shift+f2"), action: .up, display: .main, step: 20),
        Hotkey(keys: try parse("ropt+shift+f1"), action: .down, display: .secondary, step: 20),
        Hotkey(keys: try parse("ropt+shift+f2"), action: .up, display: .secondary, step: 20),
    ])
}

@Test func shiftPicksTheLargeStepAndOnlyThat() throws {
    let plain = flags(.maskAlternate, leftOption)
    let shifted = flags(.maskAlternate, leftOption, .maskShift, leftShift)
    let hits = { (f: CGEventFlags) in Hotkey.defaults.filter { $0.keys.matches(keyCode: 0x7A, flags: f) } }
    #expect(hits(plain).map(\.step) == [5])
    #expect(hits(shifted).map(\.step) == [20])
}

@Test func hotkeyDeltaFollowsActionAndStep() throws {
    #expect(Hotkey(keys: try parse("lopt+f1"), action: .down, display: .main, step: 5).delta == -5)
    #expect(Hotkey(keys: try parse("lopt+f2"), action: .up, display: .main, step: 5).delta == 5)
}

@Test func hotkeyDecodesDisplayKeywordsAndSelectors() throws {
    let decoder = JSONDecoder()
    func decode(_ json: String) throws -> Hotkey {
        try decoder.decode(Hotkey.self, from: Data(json.utf8))
    }
    #expect(try decode(#"{"keys": "lopt+f1", "action": "down"}"#)
        == Hotkey(keys: try parse("lopt+f1"), action: .down, display: .main, step: 5))
    #expect(try decode(#"{"keys": "lopt+f1", "action": "up", "display": "secondary", "step": 5}"#)
        == Hotkey(keys: try parse("lopt+f1"), action: .up, display: .secondary, step: 5))
    #expect(try decode(#"{"keys": "lopt+f1", "action": "up", "display": "all"}"#).display == .all)
    #expect(try decode(#"{"keys": "lopt+f1", "action": "up", "display": "ultrafine"}"#).display == .selector("ultrafine"))
    #expect(try decode(#"{"keys": "lopt+f1", "action": "up", "display": "2"}"#).display == .selector("2"))
}

@Test func hotkeyRejectsBadActionStepOrKeys() {
    let decoder = JSONDecoder()
    #expect(throws: DecodingError.self) {
        try decoder.decode(Hotkey.self, from: Data(#"{"keys": "lopt+f1", "action": "sideways"}"#.utf8))
    }
    #expect(throws: MBrightError.invalidHotkey(keys: "lopt+f1", reason: "step must be between 1 and 100")) {
        try decoder.decode(Hotkey.self, from: Data(#"{"keys": "lopt+f1", "action": "up", "step": 0}"#.utf8))
    }
    #expect(throws: MBrightError.invalidHotkey(keys: "lopt+f1", reason: "step must be between 1 and 100")) {
        try decoder.decode(Hotkey.self, from: Data(#"{"keys": "lopt+f1", "action": "up", "step": 101}"#.utf8))
    }
    #expect(throws: MBrightError.invalidHotkey(keys: "x", reason: "needs at least one modifier")) {
        try decoder.decode(Hotkey.self, from: Data(#"{"keys": "x", "action": "up"}"#.utf8))
    }
}

@Test func hotkeyEncodesEveryFieldAsStrings() throws {
    let hotkey = Hotkey(keys: try parse("ropt+f2"), action: .up, display: .selector("ultrafine"), step: 5)
    let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(hotkey)) as? [String: Any]
    #expect(object?["keys"] as? String == "ropt+f2")
    #expect(object?["action"] as? String == "up")
    #expect(object?["display"] as? String == "ultrafine")
    #expect(object?["step"] as? Int == 5)
    #expect(object?.count == 4)
    for target: Target in [.main, .secondary, .all] {
        let encoded = try JSONEncoder().encode(Hotkey(keys: try parse("ropt+f2"), action: .up, display: target))
        let decoded = try JSONDecoder().decode(Hotkey.self, from: encoded)
        #expect(decoded.display == target)
    }
}

@Test func hotkeyDescribesItselfForTheCLI() throws {
    #expect(Hotkey(keys: try parse("lopt+f1"), action: .down, display: .main).description == "lopt+f1  main down 5")
    #expect(Hotkey(keys: try parse("ropt+f2"), action: .up, display: .selector("lg"), step: 5).description
        == "ropt+f2  lg up 5")
}

@Test func invalidHotkeyErrorHasMessage() {
    #expect(MBrightError.invalidHotkey(keys: "lopt+f99", reason: "unknown key 'f99'").description
        == "Invalid hotkey 'lopt+f99': unknown key 'f99'")
}
