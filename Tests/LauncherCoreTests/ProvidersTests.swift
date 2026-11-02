// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import LauncherCore

final class ProvidersTests: XCTestCase {
    var dir: URL!
    var index: AppIndex!
    var usage: UsageStore!
    var engine: SearchEngine!

    override func setUpWithError() throws {
        dir = try Fixtures.tempDir()
        for (name, id) in [("Safari", "com.apple.Safari"), ("Emacs", "org.gnu.Emacs"),
                           ("Visual Studio Code", "com.microsoft.VSCode"), ("Mail", "com.apple.mail")] {
            try Fixtures.makeApp(name, in: dir, bundleID: id)
        }
        index = AppIndex(roots: [dir], extras: [])
        usage = UsageStore(url: dir.appending(path: "usage.json"))
        let store = try Fixtures.emojiStore()
        engine = SearchEngine(providers: [
            CalculatorProvider(),
            ConverterProvider(system: { .usImperial }),
            EmojiCommandProvider(),
            AppProvider(index: index, usage: usage),
            EmojiInlineProvider(store: store, aliases: { [:] }, recents: { [] }, tone: { .none }),
        ])
    }

    func ids(_ q: String) -> [String] { engine.results(for: q).map(\.id) }

    func testAppsByPrefixAndAcronym() {
        XCTAssertEqual(ids("saf").first, "app:com.apple.Safari")
        XCTAssertEqual(ids("vsc").first, "app:com.microsoft.VSCode")
    }

    func testAppResultShape() throws {
        let r = try XCTUnwrap(engine.results(for: "safari").first)
        XCTAssertEqual(r.kind, .app)
        XCTAssertEqual(r.title, "Safari")
        guard case .open(let url) = r.action else { return XCTFail("expected open") }
        XCTAssertEqual(r.alternate, .reveal(url))
        XCTAssertEqual(r.usageKey, "com.apple.Safari")
        XCTAssertEqual(r.footerHint, "↩ Open   ⌥↩ Show in Finder")
    }

    func testMathIsPinnedAndCopiesBareNumber() throws {
        let r = try XCTUnwrap(engine.results(for: "2+2*3").first)
        XCTAssertEqual(r.id, "calc")
        XCTAssertEqual(r.title, "= 8")
        XCTAssertEqual(r.action, .copy("8"))
    }

    func testConversionIsPinnedWithUnitAlternate() throws {
        let r = try XCTUnwrap(engine.results(for: "72f").first)
        XCTAssertEqual(r.id, "convert")
        XCTAssertEqual(r.title, "= 22.2222 °C")
        XCTAssertEqual(r.subtitle, "72 °F → °C")
        XCTAssertEqual(r.action, .copy("22.2222"))
        XCTAssertEqual(r.alternate, .copy("22.2222 °C"))
        XCTAssertEqual(r.footerHint, "↩ Copy   ⌥↩ Copy with unit")
    }

    func testEAndEmojiPinTheEmojiCommand() {
        XCTAssertEqual(ids("e").first, "cmd:emoji")
        XCTAssertEqual(ids("emoji").first, "cmd:emoji")
        XCTAssertEqual(ids("E").first, "cmd:emoji")
        XCTAssertTrue(ids("emo").contains("cmd:emoji"))
        XCTAssertEqual(ids("ema").first, "app:org.gnu.Emacs")
    }

    func testCloseEmojiMatchesAppearInline() {
        let r = ids("fingers crossed")
        XCTAssertTrue(r.contains("emoji:🤞"))
        XCTAssertLessThanOrEqual(r.filter { $0.hasPrefix("emoji:") }.count, 3)
        XCTAssertFalse(ids("s").contains { $0.hasPrefix("emoji:") })   // one letter: no emoji noise
    }

    /// An alias that only matches as scattered letters ("nerd" for "nd") must not earn the alias
    /// bonus that lifts it into the main list's inline emoji.
    func testAliasSubsequenceMatchIsNotInline() throws {
        let inline = EmojiInlineProvider(store: try Fixtures.emojiStore(), aliases: { ["👓": ["nerd"]] },
                                         recents: { [] }, tone: { .none })
        XCTAssertFalse(inline.results(for: Query("nd")).map(\.id).contains("emoji:👓"))
        XCTAssertTrue(inline.results(for: Query("nerd")).map(\.id).contains("emoji:👓"))
    }

    func testFrecencyReordersTies() {
        let before = ids("ma")
        XCTAssertTrue(before.contains("app:com.apple.mail"))
        for _ in 0..<5 { usage.recordLaunch("com.apple.mail") }
        XCTAssertEqual(ids("ma").first, "app:com.apple.mail")
    }

    func testRemovedAppDisappearsAfterRebuild() throws {
        try FileManager.default.removeItem(at: dir.appending(path: "Safari.app"))
        XCTAssertEqual(ids("safari").first, "app:com.apple.Safari")   // stale until re-indexed
        index.rebuild()
        XCTAssertFalse(ids("safari").contains("app:com.apple.Safari"))
    }

    func testEmptyQueryGivesNothing() {
        XCTAssertEqual(ids(""), [])
        XCTAssertEqual(ids("   "), [])
    }

    func testMergeIsStableForEqualScores() {
        struct Fixed: Provider {
            let items: [ResultItem]
            func results(for query: Query) -> [ResultItem] { items }
        }
        func item(_ id: String, _ score: Double) -> ResultItem {
            ResultItem(id: id, kind: .command, title: id, subtitle: "", icon: .symbol("x"), score: score, action: .copy(id))
        }
        let e = SearchEngine(providers: [Fixed(items: [item("a", 1), item("b", 2)]), Fixed(items: [item("c", 1)])])
        XCTAssertEqual(e.results(for: "q").map(\.id), ["b", "a", "c"])
    }
}
