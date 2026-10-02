// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MacDaddyCore

/// A process as one round sees it: a `ps` row plus what the app learns about it.
struct P {
    var pid: Int
    var ppid = 500
    var cpu: Double
    var command = "/opt/homebrew/bin/spin"
    var path: String?
    var bundleID: String?
    var thirdParty = true
    var label: String?
    var started = Date(timeIntervalSince1970: 900_000)
}

/// Feeds rounds at `t0 + at` seconds.
func round(_ h: Hoes, at: Int, _ procs: [P], rules: [HoeRule] = [], hidden: Set<String> = [],
           front: Int? = nil, frontBundle: String? = nil, forceQuitWindowAt: Date? = nil) -> Hoes.Round {
    let ps = procs.map { "  \($0.pid)  \($0.ppid)  \(String(format: "%.1f", $0.cpu)) \($0.command)" }.joined(separator: "\n")
    var details: [Int: Hoes.Detail] = [:]
    for p in procs {
        details[p.pid] = Hoes.Detail(path: p.path ?? p.command, start: p.started, bundleID: p.bundleID,
                                     thirdParty: p.thirdParty, launchdLabel: p.label)
    }
    return h.record(ps: ps, at: HoesTests.t0.addingTimeInterval(Double(at)), details: details, rules: rules, hidden: hidden,
                    frontmostPID: front, frontmostBundle: frontBundle, forceQuitWindowAt: forceQuitWindowAt, selfPID: 99)
}

final class HoesTests: XCTestCase {
    static let t0 = Date(timeIntervalSince1970: 1_000_000)
    var t0: Date { Self.t0 }
    let spin = "/opt/homebrew/bin/spin"

    /// Rounds every 30 s from `from` through `through`, returning the last.
    @discardableResult
    func feed(_ h: Hoes, from: Int = 0, through: Int, rules: [HoeRule] = [], _ procs: (Int) -> [P]) -> Hoes.Round {
        var last = Hoes.Round()
        for at in stride(from: from, through: through, by: 30) { last = round(h, at: at, procs(at), rules: rules) }
        return last
    }

    // MARK: - Who is a hoe

    func testHotThirdPartyBecomesAHoeAfterTwoMinutes() {
        let h = Hoes()
        XCTAssertEqual(feed(h, through: 90) { _ in [P(pid: 7, cpu: 99)] }.hoes, [])
        let r = round(h, at: 120, [P(pid: 7, cpu: 99)])
        XCTAssertEqual(r.hoes.map(\.pid), [7])
        XCTAssertEqual(r.hoes.first?.name, "spin")
        XCTAssertEqual(r.hoes.first?.key, spin)
        XCTAssertEqual(r.hoes.first?.minutes, 2)
        XCTAssertEqual(r.hoes.first?.meanCPU ?? 0, 99, accuracy: 0.01)
        XCTAssertEqual(r.hoes.first?.isNew, true)
        XCTAssertEqual(r.warnings, ["WARN spin pid=7 cpu=99.0% (hoe: ≥80% for 2 min)"])
        let next = round(h, at: 150, [P(pid: 7, cpu: 99)])
        XCTAssertEqual(next.hoes.first?.isNew, false)
        XCTAssertEqual(next.warnings, [])
    }

    func testAppleSignedHiddenAndSelfAreNeverHoes() {
        let h = Hoes()
        let r = feed(h, through: 300) { _ in [
            P(pid: 7, cpu: 99, command: "/usr/bin/yes", thirdParty: false),
            P(pid: 8, cpu: 99, command: "/opt/x/hidden"),
            P(pid: 99, cpu: 99, command: "/Applications/Mac Daddy.app/Contents/MacOS/MacDaddy"),
        ] }
        XCTAssertEqual(round(h, at: 330, [P(pid: 8, cpu: 99, command: "/opt/x/hidden")], hidden: ["/opt/x/hidden"]).hoes, [])
        XCTAssertEqual(r.hoes.map(\.pid), [8])   // hidden only when the caller says so
    }

    func testAppsAreNamedAndKeyedByTheirInnermostBundle() {
        let h = Hoes()
        let path = "/Applications/Big.app/Contents/Frameworks/Big Helper.app/Contents/MacOS/Big Helper"
        let r = feed(h, through: 120) { _ in [P(pid: 7, cpu: 99, command: path, bundleID: "com.big.helper")] }
        XCTAssertEqual(r.hoes.first?.name, "Big Helper")
        XCTAssertEqual(r.hoes.first?.key, "com.big.helper")
    }

    func testCoolingStartsTheStreakOver() {
        let h = Hoes()
        feed(h, through: 90) { _ in [P(pid: 7, cpu: 99)] }
        _ = round(h, at: 120, [P(pid: 7, cpu: 10)])
        XCTAssertEqual(feed(h, from: 150, through: 240) { _ in [P(pid: 7, cpu: 99)] }.hoes, [])
        XCTAssertEqual(round(h, at: 270, [P(pid: 7, cpu: 99)]).hoes.map(\.pid), [7])
    }

    func testInterestCoversHotTrackedAndRecentlyExitedPaths() {
        let h = Hoes()
        XCTAssertTrue(h.interest.wants(pid: 1, cpu: 70, command: "/x"))
        XCTAssertFalse(h.interest.wants(pid: 1, cpu: 69.9, command: "/x"))
        _ = round(h, at: 0, [P(pid: 7, cpu: 99)])
        XCTAssertTrue(h.interest.wants(pid: 7, cpu: 0, command: spin))
        feed(h, from: 30, through: 150) { _ in [P(pid: 7, cpu: 99)] }
        _ = round(h, at: 180, [])
        XCTAssertTrue(h.interest.wants(pid: 8, cpu: 0, command: spin + " --again"))
    }

    // MARK: - Learning from a force-quit

    func hoeThenGone(_ h: Hoes, last: Double = 99, endAt: Int = 180, forceQuitWindowAt: Date? = nil) -> Hoes.Round {
        feed(h, through: endAt - 60) { _ in [P(pid: 7, cpu: 99, label: "com.x.spin")] }
        _ = round(h, at: endAt - 30, [P(pid: 7, cpu: last, label: "com.x.spin")])
        return round(h, at: endAt, [], forceQuitWindowAt: forceQuitWindowAt)
    }

    func testAHoeVanishingWhileHotIsAProbableForceQuit() {
        let r = hoeThenGone(Hoes())
        XCTAssertEqual(r.forceQuits.count, 1)
        let fq = r.forceQuits[0]
        XCTAssertEqual(fq.key, spin)
        XCTAssertEqual(fq.name, "spin")
        XCTAssertEqual(fq.pid, 7)
        XCTAssertEqual(fq.meanCPU, 99, accuracy: 0.01)
        XCTAssertEqual(fq.hotSeconds, 150)
        XCTAssertEqual(fq.evidence, [])
        XCTAssertEqual(fq.launchdLabel, "com.x.spin")
        XCTAssertFalse(fq.isApp)
    }

    func testAnExitAfterCoolingDoesNotCount() {
        XCTAssertEqual(hoeThenGone(Hoes(), last: 75).forceQuits, [])   // still tracked, but under 80
        XCTAssertEqual(hoeThenGone(Hoes(), last: 10).forceQuits, [])   // no longer tracked
    }

    func testVanishingBeforeItWasAHoeDoesNotCount() {
        let h = Hoes()
        feed(h, through: 60) { _ in [P(pid: 7, cpu: 99)] }
        XCTAssertEqual(round(h, at: 90, []).forceQuits, [])
    }

    func testAppleSignedVanishingDoesNotCount() {
        let h = Hoes()
        feed(h, through: 150) { _ in [P(pid: 7, cpu: 99, thirdParty: false)] }
        XCTAssertEqual(round(h, at: 180, []).forceQuits, [])
    }

    func testActivityMonitorOrForceQuitInFrontIsEvidence() {
        XCTAssertEqual(hoeThenGone(Hoes(), forceQuitWindowAt: t0.addingTimeInterval(170)).forceQuits.first?.evidence,
                       [.forceQuitWindow])
        // Within 60 s before the last sample still counts; earlier does not.
        XCTAssertEqual(hoeThenGone(Hoes(), forceQuitWindowAt: t0.addingTimeInterval(100)).forceQuits.first?.evidence,
                       [.forceQuitWindow])
        XCTAssertEqual(hoeThenGone(Hoes(), forceQuitWindowAt: t0.addingTimeInterval(60)).forceQuits.first?.evidence, [])
    }

    func testEndedFromTheMenuIsCertain() {
        let h = Hoes()
        feed(h, through: 150) { _ in [P(pid: 7, cpu: 99)] }
        h.markEnded(pid: 7, start: P(pid: 7, cpu: 0).started, byRule: false)
        XCTAssertEqual(round(h, at: 180, []).forceQuits.first?.evidence, [.endedHere])
    }

    func testKillsByARuleDoNotCount() {
        let h = Hoes()
        feed(h, through: 150) { _ in [P(pid: 7, cpu: 99)] }
        h.markEnded(pid: 7, start: P(pid: 7, cpu: 0).started, byRule: true)
        XCTAssertEqual(round(h, at: 180, []).forceQuits, [])
    }

    func testMarkEndedIgnoresAnotherProcessOnThePID() {
        let h = Hoes()
        feed(h, through: 150) { _ in [P(pid: 7, cpu: 99)] }
        h.markEnded(pid: 7, start: t0, byRule: true)   // wrong start time
        XCTAssertEqual(round(h, at: 180, []).forceQuits.count, 1)
    }

    func testRespawnWithinAMinuteIsReported() {
        let h = Hoes()
        _ = hoeThenGone(h)
        let r = round(h, at: 210, [P(pid: 8, cpu: 1, label: "com.x.spin")])
        XCTAssertEqual(r.respawns, [Hoes.Respawn(key: spin, launchdLabel: "com.x.spin")])
        XCTAssertEqual(round(h, at: 240, [P(pid: 8, cpu: 1)]).respawns, [])   // once
    }

    func testRespawnAfterAMinuteIsNot() {
        let h = Hoes()
        _ = hoeThenGone(h)
        _ = round(h, at: 210, [])
        XCTAssertEqual(round(h, at: 270, [P(pid: 8, cpu: 1)]).respawns, [])
    }

    func testAReusedPIDMeansTheOldProcessExited() {
        let h = Hoes()
        feed(h, through: 150) { _ in [P(pid: 7, cpu: 99)] }
        let r = round(h, at: 180, [P(pid: 7, cpu: 99, command: "/opt/other", started: t0.addingTimeInterval(170))])
        XCTAssertEqual(r.forceQuits.map(\.key), [spin])
        XCTAssertEqual(r.hoes, [])   // the newcomer starts from nothing
    }

    func testNothingIsInferredAcrossSleep() {
        let h = Hoes()
        feed(h, through: 150) { _ in [P(pid: 7, cpu: 99)] }
        XCTAssertEqual(round(h, at: 150 + 600, []).forceQuits, [])
    }

    // MARK: - Rules

    let rule = HoeRule.learned(key: "/opt/homebrew/bin/spin", name: "spin", threshold: 90, minutes: 2, isApp: false, restartLabel: nil)

    func testARuleIsDueOnceItsBarHasHeldForItsDuration() {
        let h = Hoes()
        XCTAssertEqual(feed(h, through: 90, rules: [rule]) { _ in [P(pid: 7, cpu: 95)] }.due, [])
        let r = round(h, at: 120, [P(pid: 7, cpu: 95)], rules: [rule])
        XCTAssertEqual(r.due.map(\.pid), [7])
        XCTAssertEqual(r.due.first?.ruleID, rule.id)
        XCTAssertEqual(r.due.first?.cpu, "95.0")
        XCTAssertEqual(r.due.first?.seconds, 120)
        XCTAssertEqual(r.due.first?.samples, 5)
    }

    func testRuleBarComparesTheWholePercent() {
        let h = Hoes()
        XCTAssertEqual(feed(h, through: 300, rules: [rule]) { _ in [P(pid: 7, cpu: 89.9)] }.due, [])
    }

    func testRuleWarnsOncePerStreak() {
        let h = Hoes()
        XCTAssertEqual(round(h, at: 0, [P(pid: 7, cpu: 95)], rules: [rule]).warnings,
                       ["WARN spin pid=7 cpu=95.0% (≥90% for 2 min: 0 min so far)"])
        XCTAssertEqual(round(h, at: 30, [P(pid: 7, cpu: 95)], rules: [rule]).warnings, [])
        _ = round(h, at: 60, [P(pid: 7, cpu: 75)], rules: [rule])
        XCTAssertEqual(round(h, at: 90, [P(pid: 7, cpu: 95)], rules: [rule]).warnings.count, 1)
    }

    func testPausedRulesAreSkipped() {
        var paused = rule; paused.paused = true
        XCTAssertEqual(feed(Hoes(), through: 300, rules: [paused]) { _ in [P(pid: 7, cpu: 99)] }.due, [])
    }

    func testOnSightRuleIsDueAtOnce() {
        var now = rule; now.minutes = 0
        XCTAssertEqual(round(Hoes(), at: 0, [P(pid: 7, cpu: 95)], rules: [now]).due.map(\.pid), [7])
    }

    func testSkipWhileInFront() {
        var app = HoeRule.learned(key: "com.big.app", name: "Big", threshold: 90, minutes: 0, isApp: true, restartLabel: nil)
        let main = P(pid: 7, cpu: 99, command: "/Applications/Big.app/Contents/MacOS/Big", bundleID: "com.big.app")
        XCTAssertEqual(round(Hoes(), at: 0, [main], rules: [app], front: 7).due, [])
        XCTAssertEqual(round(Hoes(), at: 0, [main], rules: [app], frontBundle: "/Applications/Big.app/").due, [])
        XCTAssertEqual(round(Hoes(), at: 0, [main], rules: [app], front: 8).due.map(\.pid), [7])
        app.skipWhenFrontmost = false
        XCTAssertEqual(round(Hoes(), at: 0, [main], rules: [app], front: 7).due.map(\.pid), [7])
    }

    func testAProcessBeingEndedIsNotDueAgain() {
        let h = Hoes()
        var now = rule; now.minutes = 0
        _ = round(h, at: 0, [P(pid: 7, cpu: 95)], rules: [now])
        h.markEnded(pid: 7, start: P(pid: 7, cpu: 0).started, byRule: true)
        XCTAssertEqual(round(h, at: 30, [P(pid: 7, cpu: 95)], rules: [now]).due, [])
    }

    func testFirstMatchingUnpausedRuleWins() {
        var strict = rule; strict.id = "a"; strict.threshold = 98
        var loose = rule; loose.id = "b"; loose.minutes = 0
        XCTAssertEqual(round(Hoes(), at: 0, [P(pid: 7, cpu: 95)], rules: [strict, loose]).due, [])
        strict.paused = true
        XCTAssertEqual(round(Hoes(), at: 0, [P(pid: 7, cpu: 95)], rules: [strict, loose]).due.map(\.ruleID), ["b"])
    }

    func testKillMessage() {
        let d = Hoes.Due(pid: 7, start: t0, ruleID: rule.id, name: "spin", command: spin, cpu: "95.0",
                         meanCPU: 95, seconds: 150, samples: 6)
        XCTAssertEqual(Hoes.killMessage(d, rule: rule), "KILLED runaway spin pid=7 cpu=95.0% (≥90% for 2 min, rule \"spin\")")
    }
}
