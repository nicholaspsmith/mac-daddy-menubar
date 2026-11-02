// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import LauncherCore

final class AliasTableTests: XCTestCase {
    var store: EmojiStore!
    override func setUpWithError() throws { store = try Fixtures.emojiStore() }

    func rows(search: String = "", group: String? = nil, withAliases: Bool = false, recent: Bool = false) -> [AliasRow] {
        AliasTable.rows(store: store, aliases: ["👓": ["nerd", "specs"]], recents: ["🎉"],
                        search: search, group: group, onlyWithAliases: withAliases, onlyRecent: recent)
    }

    func testAllRowsByDefault() {
        XCTAssertEqual(rows().count, store.all.count)
        XCTAssertEqual(rows().first { $0.char == "👓" }?.aliasText, "nerd, specs")
    }

    func testSearchUsesTheEmojiMatcher() {
        XCTAssertEqual(rows(search: "crossed fingers").first?.char, "🤞")
        XCTAssertEqual(rows(search: "specs").first?.char, "👓")
    }

    func testFilters() {
        XCTAssertEqual(rows(withAliases: true).map(\.char), ["👓"])
        XCTAssertEqual(rows(recent: true).map(\.char), ["🎉"])
        XCTAssertTrue(rows(group: "Flags").allSatisfy { $0.group == "Flags" })
        XCTAssertFalse(rows(group: "Flags").isEmpty)
    }
}
