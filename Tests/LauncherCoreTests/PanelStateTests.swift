// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import LauncherCore

final class PanelStateTests: XCTestCase {
    struct Words: Provider {
        func results(for query: Query) -> [ResultItem] {
            (0..<12).map { i in
                ResultItem(id: "\(query.folded)-\(i)", kind: .command, title: "\(i)", subtitle: "",
                           icon: .symbol("x"), score: Double(100 - i), action: .copy("\(i)"))
            }.filter { _ in query.folded != "none" }
        }
    }
    static let emoji = (0..<20).map { i in
        EmojiHit(emoji: Emoji(char: "e\(i)", name: "n\(i)", keywords: [], group: "g", tones: nil), score: 1)
    }
    func make() -> PanelState {
        PanelState(engine: SearchEngine(providers: [Words()]), gridColumns: 9) { q in
            q.isEmpty ? Self.emoji : Array(Self.emoji.prefix(3))
        }
    }

    func testTypingSearchesAndResetsSelection() {
        let s = make()
        s.query = "a"
        XCTAssertEqual(s.results.count, 12)
        s.move(3)
        XCTAssertEqual(s.selection, 3)
        s.query = "ab"
        XCTAssertEqual(s.selection, 0)
    }

    func testMoveClamps() {
        let s = make()
        s.query = "a"
        s.move(-1); XCTAssertEqual(s.selection, 0)
        s.move(50); XCTAssertEqual(s.selection, 11)
    }

    func testSelectIndexForCommandDigits() {
        let s = make()
        s.query = "a"
        XCTAssertTrue(s.select(index: 4)); XCTAssertEqual(s.selection, 4)
        XCTAssertFalse(s.select(index: 20)); XCTAssertEqual(s.selection, 4)
    }

    func testEscapeInMainClearsThenCloses() {
        let s = make()
        s.query = "a"
        XCTAssertEqual(s.escape(), .clearedQuery)
        XCTAssertEqual(s.query, "")
        XCTAssertEqual(s.escape(), .close)
    }

    func testEmojiModeEnterEscapeAndBackspace() {
        let s = make()
        s.query = "e"
        s.enterEmojiMode()
        XCTAssertEqual(s.mode, .emoji)
        XCTAssertEqual(s.query, "")
        XCTAssertEqual(s.emoji.count, 20)
        s.query = "fire"
        XCTAssertEqual(s.escape(), .backToMain)          // even with text typed
        XCTAssertEqual(s.mode, .main)
        XCTAssertEqual(s.query, "")
        s.enterEmojiMode()
        XCTAssertTrue(s.deleteOnEmpty())
        XCTAssertEqual(s.mode, .main)
        XCTAssertFalse(s.deleteOnEmpty())                // main mode: backspace is just backspace
    }

    func testGridMovement() {
        let s = make()
        s.enterEmojiMode()
        s.moveGrid(dx: 1, dy: 0); XCTAssertEqual(s.selection, 1)
        s.moveGrid(dx: 0, dy: 1); XCTAssertEqual(s.selection, 10)
        s.moveGrid(dx: 0, dy: 1); XCTAssertEqual(s.selection, 19)   // clamps to last
        s.moveGrid(dx: -1, dy: -5); XCTAssertEqual(s.selection, 0)
    }

    func testMissAndReset() {
        let s = make()
        XCTAssertFalse(s.isMiss)
        s.query = "none"
        XCTAssertTrue(s.isMiss)
        s.footerMessage = "Copied"
        s.enterEmojiMode()
        s.reset()
        XCTAssertEqual(s.mode, .main)
        XCTAssertEqual(s.query, "")
        XCTAssertNil(s.footerMessage)
        XCTAssertEqual(s.results, [])
    }
}
