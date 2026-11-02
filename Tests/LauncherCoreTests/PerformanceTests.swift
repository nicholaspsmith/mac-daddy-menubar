// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import XCTest
import LauncherCore
import Darwin

final class PerformanceTests: XCTestCase {
    func testOneKeystrokeUnderFiveMilliseconds() throws {
        // The budget is for typing at interactive priority. A background job
        // (a LaunchAgent with ProcessType Background runs at background QoS; taskpolicy -b
        // sets the Darwin background flag) is held to the
        // efficiency cores and runs this 3-4x slower, so the number means nothing.
        if getpriority(PRIO_DARWIN_PROCESS, 0) != 0 || qos_class_self().rawValue <= QOS_CLASS_UTILITY.rawValue {
            throw XCTSkip("running at background priority; the keystroke budget is measured at interactive priority")
        }
        let dir = FileManager.default.temporaryDirectory.appending(path: "launcher-perf-\(UUID().uuidString)")
        for i in 0..<150 {
            let contents = dir.appending(path: "App Number \(i).app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist = ["CFBundleIdentifier": "com.perf.app\(i)"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appending(path: "Info.plist"))
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let store = try EmojiStore(data: Data(contentsOf: root.appending(path: "Resources/bundle/emoji.json")))
        let engine = SearchEngine(providers: [
            CalculatorProvider(), ConverterProvider(system: { .usImperial }), EmojiCommandProvider(),
            AppProvider(index: AppIndex(roots: [dir], extras: []), usage: UsageStore(url: dir.appending(path: "u.json"))),
            EmojiInlineProvider(store: store, aliases: { [:] }, recents: { [] }, tone: { .none }),
        ])
        let queries = ["s", "sa", "saf", "safari", "fingers crossed", "72f to c", "2+2*3", "emoji", "xyzzy", "thumbs up", "app num"]
        _ = engine.results(for: "warm")
        // Best of several rounds: a busy machine (parallel builds, a local LLM)
        // slows some rounds, but a real regression slows every one of them.
        let runs = 10
        var perQueryMs = Double.infinity
        for _ in 0..<5 {
            let start = Date()
            for _ in 0..<runs { for q in queries { _ = engine.results(for: q) } }
            perQueryMs = min(perQueryMs, Date().timeIntervalSince(start) * 1000 / Double(runs * queries.count))
        }
        print("per-query (best of 5): \(perQueryMs) ms")
        XCTAssertLessThan(perQueryMs, 5)
    }
}
