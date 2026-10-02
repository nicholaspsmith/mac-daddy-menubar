// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MacDaddyCore

final class HoesStateTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let spin = "/opt/homebrew/bin/spin"

    func fq(key: String? = nil, mean: Double = 99, hot: TimeInterval = 600, evidence: [Hoes.Evidence] = [],
            label: String? = nil, isApp: Bool = false, command: String? = nil) -> Hoes.ForceQuit {
        Hoes.ForceQuit(pid: 7, key: key ?? spin, name: "spin", command: command ?? spin, ppid: 500, isApp: isApp,
                       meanCPU: mean, hotSeconds: hot, evidence: evidence, launchdLabel: label)
    }

    func testAForceQuitBecomesASuggestionWithTheGuess() {
        var s = HoesState()
        guard case .suggested(let sug) = s.learn(fq(evidence: [.forceQuitWindow], label: "com.x.spin"), now: now) else {
            return XCTFail("expected a suggestion")
        }
        XCTAssertEqual(sug.key, spin)
        XCTAssertEqual(sug.threshold, 90)
        XCTAssertEqual(sug.minutes, 5)
        XCTAssertEqual(sug.meanCPU, 99)
        XCTAssertEqual(sug.observedMinutes, 10)
        XCTAssertEqual(sug.restartLabel, "com.x.spin")
        XCTAssertEqual(sug.evidence, [.forceQuitWindow])
        XCTAssertEqual(s.suggestions, [sug])
        XCTAssertEqual(sug.prompt(.pimp), "Auto pimp slap spin? (≥90% for 5 min)")
        XCTAssertEqual(sug.notification(.pimp), "You pimp slapped spin after 10 min at 99% CPU. Pimp slap it automatically next time?")
        XCTAssertEqual(sug.prompt(.normal), "Auto-kill spin? (≥90% for 5 min)")
    }

    func testASecondForceQuitReplacesThePendingSuggestion() {
        var s = HoesState()
        _ = s.learn(fq(), now: now)
        _ = s.learn(fq(hot: 240), now: now)
        XCTAssertEqual(s.suggestions.count, 1)
        XCTAssertEqual(s.suggestions.first?.minutes, 2)
    }

    func testIgnoredAndDeclinedAreNeverSuggested() {
        var s = HoesState()
        s.ignore(key: spin, name: "spin")
        XCTAssertEqual(s.learn(fq(), now: now), .skipped)
        var d = HoesState()
        _ = d.learn(fq(), now: now)
        d.decline(key: spin)
        XCTAssertEqual(d.suggestions, [])
        XCTAssertEqual(d.ignored, [HoesState.Ignored(key: spin, name: "spin", hidden: false)])
        XCTAssertEqual(d.learn(fq(), now: now), .skipped)
        XCTAssertEqual(d.hiddenKeys, [])   // still listed as a hoe
        d.unignore(key: spin)
        XCTAssertEqual(d.ignored, [])
        if case .suggested = d.learn(fq(), now: now) {} else { XCTFail("expected a suggestion after un-ignoring") }
    }

    func testIgnoreHidesAndDropsAPendingSuggestion() {
        var s = HoesState()
        _ = s.learn(fq(), now: now)
        s.ignore(key: spin, name: "spin")
        XCTAssertEqual(s.suggestions, [])
        XCTAssertEqual(s.hiddenKeys, [spin])
    }

    func testAcceptTurnsTheSuggestionIntoARule() {
        var s = HoesState()
        _ = s.learn(fq(label: "com.x.spin", isApp: true), now: now)
        let r = s.accept(key: spin)
        XCTAssertEqual(r?.match, .executable(spin))
        XCTAssertEqual(r?.threshold, 90)
        XCTAssertEqual(r?.minutes, 5)
        XCTAssertEqual(r?.restartLabel, "com.x.spin")
        XCTAssertEqual(r?.skipWhenFrontmost, true)
        XCTAssertEqual(s.rules, [r!])
        XCTAssertEqual(s.suggestions, [])
        XCTAssertNil(s.accept(key: spin))
    }

    func testAForceQuitWithARuleTightensIt() {
        var s = HoesState()
        _ = s.learn(fq(), now: now)
        _ = s.accept(key: spin)
        guard case .tightened(let r) = s.learn(fq(mean: 92, hot: 240), now: now) else { return XCTFail("expected tightening") }
        XCTAssertEqual(r.threshold, 80)   // 82 → 80
        XCTAssertEqual(r.minutes, 2)
        XCTAssertEqual(r.tightenedAt, now)
        XCTAssertEqual(s.rules, [r])
        XCTAssertEqual(s.learn(fq(), now: now), .unchanged(r))
        XCTAssertEqual(s.suggestions, [])
    }

    func testBuiltInsAreNeverTightenedNorSuggestedOver() {
        var s = HoesState()
        s.ensureBuiltIns(UAWatchdog.builtInRules, paused: false)
        let engine = "/Library/Application Support/Universal Audio/Apollo/UA Mixer Engine.app/Contents/MacOS/UA Mixer Engine"
        XCTAssertEqual(s.learn(fq(key: engine, command: engine + " -silent"), now: now), .skipped)
        XCTAssertEqual(s.rules, UAWatchdog.builtInRules)
        XCTAssertEqual(s.suggestions, [])
    }

    func testRespawnAddsEvidenceAndTheLaunchdLabel() {
        var s = HoesState()
        _ = s.learn(fq(), now: now)
        s.noteRespawn(Hoes.Respawn(key: spin, launchdLabel: "com.x.spin"))
        XCTAssertEqual(s.suggestions.first?.evidence, [.respawned])
        XCTAssertEqual(s.suggestions.first?.restartLabel, "com.x.spin")
        _ = s.accept(key: spin)
        var t = HoesState()
        _ = t.learn(fq(), now: now)
        _ = t.accept(key: spin)
        t.noteRespawn(Hoes.Respawn(key: spin, launchdLabel: "com.x.spin"))
        XCTAssertEqual(t.rules.first?.restartLabel, "com.x.spin")
    }

    func testBuiltInsAreAddedOnceKeepingAdjustments() {
        var s = HoesState()
        s.ensureBuiltIns(UAWatchdog.builtInRules, paused: true)
        XCTAssertEqual(s.rules.map(\.id), ["ua.helper", "ua.engine", "ua.other"])
        XCTAssertTrue(s.rules.allSatisfy(\.paused))
        s.rules[1].threshold = 95
        s.rules[1].paused = false
        s.ensureBuiltIns(UAWatchdog.builtInRules, paused: true)
        XCTAssertEqual(s.rules.count, 3)
        XCTAssertEqual(s.rules[1].threshold, 95)
        XCTAssertFalse(s.rules[1].paused)
    }

    func testBuiltInsCannotBeDeleted() {
        var s = HoesState()
        s.ensureBuiltIns(UAWatchdog.builtInRules, paused: false)
        _ = s.learn(fq(), now: now)
        _ = s.accept(key: spin)
        XCTAssertFalse(s.deleteRule(id: "ua.engine"))
        XCTAssertTrue(s.deleteRule(id: spin))
        XCTAssertEqual(s.rules.map(\.id), ["ua.helper", "ua.engine", "ua.other"])
    }

    func testPersistenceRoundTrip() {
        let suite = "MacDaddyTests.hoes.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertEqual(HoesState.load(from: d), HoesState())
        var s = HoesState()
        s.ensureBuiltIns(UAWatchdog.builtInRules, paused: false)
        _ = s.learn(fq(), now: now)
        _ = s.accept(key: spin)
        _ = s.learn(fq(key: "/opt/b"), now: now)
        s.ignore(key: "/opt/c", name: "c")
        s.save(to: d)
        XCTAssertNotNil(d.data(forKey: "hoes.rules"))
        XCTAssertNotNil(d.data(forKey: "hoes.suggestions"))
        XCTAssertNotNil(d.data(forKey: "hoes.ignored"))
        XCTAssertEqual(HoesState.load(from: d), s)
    }
}
