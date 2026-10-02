// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MacDaddyCore

final class HoeRuleTests: XCTestCase {
    // MARK: - Matching

    func testLearnedRuleMatchesItsKeyOnly() {
        let r = HoeRule.learned(key: "/opt/homebrew/bin/spin", name: "spin", threshold: 90, minutes: 2, isApp: false, restartLabel: nil)
        XCTAssertTrue(r.matches(command: "/opt/homebrew/bin/spin --fast", ppid: 500, key: "/opt/homebrew/bin/spin"))
        XCTAssertFalse(r.matches(command: "/opt/homebrew/bin/spin", ppid: 500, key: "/opt/homebrew/bin/other"))
        XCTAssertFalse(r.matches(command: "/opt/homebrew/bin/spin", ppid: 500, key: nil))
    }

    func testCommandMatchWithExclusionsAndOrphanedOnly() {
        let r = HoeRule(id: "x", name: "x", match: .command(any: ["Foo", "Bar"], none: ["Baz"], orphanedOnly: true),
                        threshold: 90, minutes: 1)
        XCTAssertTrue(r.matches(command: "/a/Foo", ppid: 1, key: nil))
        XCTAssertTrue(r.matches(command: "/a/Bar", ppid: 1, key: "whatever"))
        XCTAssertFalse(r.matches(command: "/a/Foo", ppid: 2, key: nil))      // not orphaned
        XCTAssertFalse(r.matches(command: "/a/Foo Baz", ppid: 1, key: nil))  // excluded
        XCTAssertFalse(r.matches(command: "/a/Qux", ppid: 1, key: nil))
    }

    func testLearnedAppsSkipWhileInFrontByDefault() {
        XCTAssertTrue(HoeRule.learned(key: "com.x.app", name: "X", threshold: 90, minutes: 2, isApp: true, restartLabel: nil).skipWhenFrontmost)
        XCTAssertFalse(HoeRule.learned(key: "/bin/x", name: "x", threshold: 90, minutes: 2, isApp: false, restartLabel: nil).skipWhenFrontmost)
        let r = HoeRule.learned(key: "/bin/x", name: "x", threshold: 90, minutes: 2, isApp: false, restartLabel: nil)
        XCTAssertEqual(r.action, .terminate)
        XCTAssertFalse(r.builtIn)
        XCTAssertFalse(r.paused)
    }

    func testRestartOnlyWhenOnAndLabelKnown() {
        var r = HoeRule(id: "x", name: "x", match: .executable("k"), threshold: 90, minutes: 1, restartLabel: "com.x.agent")
        XCTAssertNil(r.restart(after: "/a/x"))   // off by default
        r.restartAfterKill = true
        XCTAssertEqual(r.restart(after: "/a/x"), "com.x.agent")
        r.restartOnlyIf = ["Helper.app"]
        XCTAssertNil(r.restart(after: "/a/x"))
        XCTAssertEqual(r.restart(after: "/a/Helper.app/x"), "com.x.agent")
        r.restartLabel = nil
        XCTAssertNil(r.restart(after: "/a/Helper.app/x"))
    }

    func testSummary() {
        XCTAssertEqual(HoeRule(id: "x", name: "x", match: .executable("k"), threshold: 90, minutes: 2).summary, "≥90% for 2 min")
        XCTAssertEqual(HoeRule(id: "x", name: "x", match: .executable("k"), threshold: 80, minutes: 0).summary, "≥80% on sight")
    }

    // MARK: - The guess

    func testGuessIsMeanLessTenRoundedToFive() {
        XCTAssertEqual(HoeRule.guess(meanCPU: 99.5, hotSeconds: 600).threshold, 90)   // 89.5 → 90
        XCTAssertEqual(HoeRule.guess(meanCPU: 97, hotSeconds: 600).threshold, 85)     // 87 → 85
        XCTAssertEqual(HoeRule.guess(meanCPU: 102.6, hotSeconds: 600).threshold, 95)  // 92.6 → 95
    }

    func testGuessThresholdIsClamped() {
        XCTAssertEqual(HoeRule.guess(meanCPU: 82, hotSeconds: 600).threshold, 80)
        XCTAssertEqual(HoeRule.guess(meanCPU: 400, hotSeconds: 600).threshold, 98)   // multi-core
    }

    func testGuessDurationIsHalfTheHotTime() {
        XCTAssertEqual(HoeRule.guess(meanCPU: 99, hotSeconds: 600).minutes, 5)
        XCTAssertEqual(HoeRule.guess(meanCPU: 99, hotSeconds: 450).minutes, 4)    // 3.75 → 4
        XCTAssertEqual(HoeRule.guess(meanCPU: 99, hotSeconds: 120).minutes, 2)    // 1 → at least 2
        XCTAssertEqual(HoeRule.guess(meanCPU: 99, hotSeconds: 7200).minutes, 30)  // 60 → at most 30
    }

    func testTightenTakesTheLowerOfEach() {
        var r = HoeRule(id: "x", name: "x", match: .executable("k"), threshold: 90, minutes: 5)
        XCTAssertTrue(r.tighten(threshold: 85, minutes: 10))
        XCTAssertEqual(r.threshold, 85); XCTAssertEqual(r.minutes, 5)
        XCTAssertTrue(r.tighten(threshold: 95, minutes: 2))
        XCTAssertEqual(r.threshold, 85); XCTAssertEqual(r.minutes, 2)
        XCTAssertFalse(r.tighten(threshold: 90, minutes: 3))
        XCTAssertEqual(r.threshold, 85); XCTAssertEqual(r.minutes, 2)
    }

    func testCodableRoundTrip() throws {
        var r = HoeRule.learned(key: "com.x.app", name: "X", threshold: 85, minutes: 3, isApp: true, restartLabel: "com.x.agent")
        r.tightenedAt = Date(timeIntervalSince1970: 1_000)
        let all = [r] + UAWatchdog.builtInRules
        XCTAssertEqual(try JSONDecoder().decode([HoeRule].self, from: JSONEncoder().encode(all)), all)
    }
}
