// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import XCTest
import HotkeyKit
@testable import LauncherCore

final class HotkeySettingsTests: XCTestCase {
    var defaults: UserDefaults!
    override func setUp() {
        defaults = UserDefaults(suiteName: "menucrane-tests-\(UUID().uuidString)")
    }

    func testDefaultIsCommandSpace() {
        XCTAssertEqual(HotkeySettings.load(from: defaults), .key(49, [.command]))
    }

    func testRoundTrip() {
        HotkeySettings.save(.key(49, [.option]), to: defaults)
        XCTAssertEqual(HotkeySettings.load(from: defaults), .key(49, [.option]))
        XCTAssertEqual(defaults.integer(forKey: HotkeySettings.keyCodeKey), 49)
        XCTAssertEqual(defaults.integer(forKey: HotkeySettings.modifiersKey), Modifiers.option.rawValue)
    }

    func testNoModifiersFallsBackToDefault() {
        defaults.set(49, forKey: HotkeySettings.keyCodeKey)
        defaults.set(0, forKey: HotkeySettings.modifiersKey)
        XCTAssertEqual(HotkeySettings.load(from: defaults), HotkeySettings.defaultTrigger)
    }

    /// macOS sets fn on arrows, Home/End, PgUp/PgDn and forward-delete, so fn alone must not
    /// count as a modifier — a saved "fn+↓" would register a bare ↓ system-wide.
    func testFnOnlyModifiersFallBackToDefault() {
        defaults.set(125, forKey: HotkeySettings.keyCodeKey)
        defaults.set(Modifiers.fn.rawValue, forKey: HotkeySettings.modifiersKey)
        XCTAssertEqual(HotkeySettings.load(from: defaults), HotkeySettings.defaultTrigger)
    }

    func testOutOfRangeKeyCodeFallsBackToDefault() {
        defaults.set(70_000, forKey: HotkeySettings.keyCodeKey)
        defaults.set(Modifiers.command.rawValue, forKey: HotkeySettings.modifiersKey)
        XCTAssertEqual(HotkeySettings.load(from: defaults), HotkeySettings.defaultTrigger)
        defaults.set(-1, forKey: HotkeySettings.keyCodeKey)
        XCTAssertEqual(HotkeySettings.load(from: defaults), HotkeySettings.defaultTrigger)
    }

    func testHasRealModifierIgnoresFn() {
        XCTAssertFalse(HotkeySettings.hasRealModifier([]))
        XCTAssertFalse(HotkeySettings.hasRealModifier([.fn]))
        XCTAssertTrue(HotkeySettings.hasRealModifier([.fn, .control]))
        XCTAssertTrue(HotkeySettings.hasRealModifier([.option]))
    }

    func testDescribe() {
        XCTAssertEqual(TriggerText.describe(.key(49, [.command])), "⌘Space")
        XCTAssertEqual(TriggerText.describe(.key(40, [.command, .shift, .option, .control])), "⌃⌥⇧⌘K")
        XCTAssertEqual(TriggerText.describe(.key(96, [.control])), "⌃F5")
        XCTAssertEqual(TriggerText.describe(.key(200, [.command])), "⌘Key 200")
    }

    func testRebindAdoptsTheNewTriggerOnSuccess() {
        let decision = HotkeyRebind.decide(new: .key(49, [.option, .control]), failure: nil, previous: .key(49, [.command]))
        XCTAssertEqual(decision.trigger, .key(49, [.option, .control]))
        XCTAssertNil(decision.message)
    }

    func testRebindKeepsThePreviousTriggerOnFailure() {
        let decision = HotkeyRebind.decide(new: .key(49, [.option]), failure: "⌥Space is in use by Raycast", previous: .key(49, [.command]))
        XCTAssertEqual(decision.trigger, .key(49, [.command]))
        XCTAssertEqual(decision.message, "⌥Space is in use by Raycast — kept ⌘Space")
    }
}
