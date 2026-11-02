// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import LauncherCore

final class EmojiStoreTests: XCTestCase {
    var store: EmojiStore!
    override func setUpWithError() throws { store = try Fixtures.emojiStore() }

    func top(_ q: String, aliases: [String: [String]] = [:], recents: [String] = []) -> [String] {
        store.search(Query(q), aliases: aliases, recents: recents).map(\.emoji.char)
    }

    func testDataLoaded() {
        XCTAssertGreaterThan(store.all.count, 1800)
        XCTAssertFalse(store.groups.contains("Component"))
        XCTAssertEqual(store.groups.first, "Smileys & Emotion")
    }

    func testCrossedFingersAnyWordOrder() {
        XCTAssertEqual(top("fingers crossed").first, "🤞")
        XCTAssertEqual(top("crossed fingers").first, "🤞")
        XCTAssertEqual(top("cross fing").first, "🤞")
        XCTAssertTrue(top("luck").prefix(10).contains("🤞"))
    }

    func testUserAliasOutranksBuiltInNames() {
        XCTAssertEqual(top("nerd", aliases: ["👓": ["nerd"]]).first, "👓")
    }

    func testEmptyQueryShowsRecentsThenEverything() {
        let r = top("", recents: ["🎉", "👍"])
        XCTAssertEqual(Array(r.prefix(2)), ["🎉", "👍"])
        XCTAssertEqual(r.count, store.all.count)
        XCTAssertEqual(r.filter { $0 == "🎉" }.count, 1)
    }

    func testRecentsBreakTies() {
        let plain = top("heart")
        let second = plain[1]
        XCTAssertEqual(top("heart", recents: [second]).first, second)
    }

    func testToneGlyphIsExactScalarSequence() throws {
        let thumbs = try XCTUnwrap(store.emoji(for: "👍"))
        XCTAssertEqual(thumbs.glyph(.medium).unicodeScalars.map(\.value), [0x1F44D, 0x1F3FD])
        XCTAssertEqual(thumbs.glyph(.none), "👍")
        let couple = try XCTUnwrap(store.emoji(for: "🧑‍🤝‍🧑"))
        XCTAssertEqual(couple.glyph(.dark), "🧑🏿‍🤝‍🧑🏿")
        let rocket = try XCTUnwrap(store.emoji(for: "🚀"))
        XCTAssertEqual(rocket.glyph(.dark), "🚀")   // no tones: unchanged
    }

    func testAliasesAndRecentsUseBaseEmoji() {
        // Aliases/recents are stored against the base emoji, so they find it whatever tone is chosen.
        let hits = store.search(Query("yes"), aliases: ["👍": ["yes"]], recents: ["👍"])
        XCTAssertEqual(hits.first?.emoji.char, "👍")
        XCTAssertEqual(hits.first?.emoji.glyph(.dark), "👍🏿")
    }

    func testSkinToneCycle() {
        XCTAssertEqual(SkinTone.none.next, .light)
        XCTAssertEqual(SkinTone.dark.next, SkinTone.none)
        XCTAssertEqual(SkinTone.medium.swatch, "✋🏽")
    }
}
