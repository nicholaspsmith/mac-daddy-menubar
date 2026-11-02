// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics
import XCTest
import HotkeyKit
@testable import LauncherCore

final class SpotlightShortcutTests: XCTestCase {
    func entry(_ params: [Any], enabled: Any = true) -> [String: Any] {
        [SpotlightShortcut.entryID: ["enabled": enabled, "value": ["type": "standard", "parameters": params]]]
    }

    func testOptionSpaceAsStoredOnThisMac() {
        XCTAssertEqual(SpotlightShortcut.parse(entry([32, 49, 524288])), .key(.key(49, [.option])))
    }

    func testDefaultCommandSpace() {
        XCTAssertEqual(SpotlightShortcut.parse(entry([32, 49, 1048576])), .key(.key(49, [.command])))
    }

    func testRebindToControlShiftKey() {
        // ⌃⇧K: 'k' (107), key code 40, control (262144) + shift (131072)
        XCTAssertEqual(SpotlightShortcut.parse(entry([107, 40, 393216])), .key(.key(40, [.control, .shift])))
    }

    func testIgnoresNonModifierBits() {
        // A numeric-pad bit on top of ⌥ is not a modifier and is dropped.
        let mask = 524288 | 0x200000   // ⌥ + numeric pad
        XCTAssertEqual(SpotlightShortcut.parse(entry([32, 49, mask])), .key(.key(49, [.option])))
    }

    func testNumbersAsStrings() {
        XCTAssertEqual(SpotlightShortcut.parse(entry(["32", "49", "524288"], enabled: "1")), .key(.key(49, [.option])))
    }

    func testDisabled() {
        XCTAssertEqual(SpotlightShortcut.parse(entry([32, 49, 524288], enabled: false)), .disabled)
        XCTAssertEqual(SpotlightShortcut.parse(entry([32, 49, 524288], enabled: 0)), .disabled)
    }

    func testFallbacks() {
        let fallback = SpotlightShortcut.Binding.key(SpotlightShortcut.fallback)
        XCTAssertEqual(SpotlightShortcut.fallback, .key(49, [.option]))
        XCTAssertEqual(SpotlightShortcut.parse(nil), fallback)
        XCTAssertEqual(SpotlightShortcut.parse("garbage"), fallback)
        XCTAssertEqual(SpotlightShortcut.parse(["65": ["enabled": true]]), fallback)   // only the file-search entry
        XCTAssertEqual(SpotlightShortcut.parse(entry([32, 49])), fallback)              // too few parameters
        XCTAssertEqual(SpotlightShortcut.parse(entry([65535, 65535, 0])), fallback)     // unbound
        XCTAssertEqual(SpotlightShortcut.parse(entry([32, 49, 0])), fallback)           // bare Space
        XCTAssertEqual(SpotlightShortcut.parse([SpotlightShortcut.entryID: ["enabled": true]]), fallback)
    }

    func testEnabledMissingCountsAsOn() {
        let e: [String: Any] = [SpotlightShortcut.entryID: ["value": ["parameters": [32, 49, 524288]]]]
        XCTAssertEqual(SpotlightShortcut.parse(e), .key(.key(49, [.option])))
    }
}

final class SpotlightWindowTests: XCTestCase {
    func win(_ n: Int, owner: String, pid: Int32 = 1, layer: Int = 23, alpha: Double = 1) -> [String: Any] {
        [kCGWindowNumber as String: n, kCGWindowOwnerName as String: owner, kCGWindowOwnerPID as String: pid,
         kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha]
    }

    func testSiriPanelOnMacOS27() {
        XCTAssertTrue(SpotlightWindow.isPanel(win(101, owner: "Siri"), bundleID: "com.apple.campo"))
        XCTAssertTrue(SpotlightWindow.isPanel(win(101, owner: "Siri"), bundleID: nil))
    }

    func testOlderSpotlight() {
        XCTAssertTrue(SpotlightWindow.isPanel(win(7, owner: "Spotlight"), bundleID: "com.apple.Spotlight"))
    }

    func testBundleIDWinsOverLocalizedOwnerName() {
        XCTAssertTrue(SpotlightWindow.isPanel(win(7, owner: "Recherche"), bundleID: "com.apple.Spotlight"))
    }

    func testRejectsOtherWindows() {
        XCTAssertFalse(SpotlightWindow.isPanel(win(1, owner: "Zen"), bundleID: "app.zen-browser.zen"))
        XCTAssertFalse(SpotlightWindow.isPanel(win(2, owner: "Siri", layer: 0), bundleID: "com.apple.campo"))
        XCTAssertFalse(SpotlightWindow.isPanel(win(3, owner: "Siri", alpha: 0), bundleID: "com.apple.campo"))
    }

    func testPanelIDs() {
        let list = [win(1, owner: "Zen", pid: 10), win(101, owner: "Siri", pid: 20), win(5, owner: "Dock", pid: 30)]
        let ids = SpotlightWindow.panelIDs(in: list) { $0 == 20 ? "com.apple.campo" : nil }
        XCTAssertEqual(ids, [101])
    }
}

final class TypingChunksTests: XCTestCase {
    func testShortTextIsOneChunk() {
        XCTAssertEqual(TypingChunks.split("weather"), ["weather"])
        XCTAssertEqual(TypingChunks.split(""), [])
    }

    func testLongTextSplitsAtTwentyUnits() {
        let s = String(repeating: "a", count: 45)
        XCTAssertEqual(TypingChunks.split(s).map(\.count), [20, 20, 5])
        XCTAssertEqual(TypingChunks.split(s).joined(), s)
    }

    func testNeverSplitsAnEmoji() {
        // 19 letters then a 2-unit emoji: the emoji moves whole into the next chunk.
        let s = String(repeating: "x", count: 19) + "🤞" + "é"
        let chunks = TypingChunks.split(s)
        XCTAssertEqual(chunks, [String(repeating: "x", count: 19), "🤞é"])
        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count <= 20 })
    }

    func testZWJSequenceStaysWhole() {
        let family = "👨‍👩‍👧‍👦"   // 11 UTF-16 units
        let s = String(repeating: family, count: 3)
        let chunks = TypingChunks.split(s)
        XCTAssertEqual(chunks, [family, family, family])
        XCTAssertEqual(chunks.joined(), s)
    }

    func testPunctuationAndNonLatin() {
        XCTAssertEqual(TypingChunks.split("€5 → ¥? «ça» 東京").joined(), "€5 → ¥? «ça» 東京")
    }
}
