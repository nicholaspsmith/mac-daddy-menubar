// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MacDaddyCore

/// The UA built-in Hoes rules reproduce the old `ua-watchdog.sh` agent, sampled
/// every 30 s instead of every 60 s.
final class UAWatchdogTests: XCTestCase {
    let helper = "/Applications/Universal Audio/UAD Console.app/Contents/Helpers/UA Mixer Helper.app/Contents/MacOS/UA Mixer Helper"
    let engine = "/Library/Application Support/Universal Audio/Apollo/UA Mixer Engine.app/Contents/MacOS/UA Mixer Engine -silent"
    let connect = "/Applications/UA Connect.app/Contents/MacOS/UA Connect --no-window"
    let meter = "/Applications/Universal Audio/UAD Meter & Control Panel.app/Contents/MacOS/UAD Meter & Control Panel -h"
    let console = "/Applications/Universal Audio/UAD Console.app/Contents/MacOS/UAD Console"
    let rules = UAWatchdog.builtInRules

    func p(_ pid: Int, ppid: Int = 500, cpu: Double, _ command: String) -> P {
        P(pid: pid, ppid: ppid, cpu: cpu, command: command)
    }

    func rule(_ id: String) -> HoeRule { rules.first { $0.id == id }! }

    /// Rounds every 30 s, returning the last.
    func feed(_ h: Hoes, from: Int = 0, through: Int, _ procs: [P]) -> Hoes.Round {
        var last = Hoes.Round()
        for at in stride(from: from, through: through, by: 30) { last = round(h, at: at, procs, rules: rules) }
        return last
    }

    // MARK: - Which processes, and what they are called

    func testOnlyUAProcessesCount() {
        XCTAssertTrue(UAWatchdog.isUA(helper))
        XCTAssertTrue(UAWatchdog.isUA(connect))
        XCTAssertTrue(UAWatchdog.isUA("/opt/x/UA Mixer Sentinel"))
        XCTAssertFalse(UAWatchdog.isUA("/Applications/Safari.app/Contents/MacOS/Safari"))
        XCTAssertFalse(UAWatchdog.isUA("/usr/sbin/coreaudiod"))
    }

    func testLabels() {
        XCTAssertEqual(UAWatchdog.label(helper), "UA Mixer Helper")
        XCTAssertEqual(UAWatchdog.label(engine), "UA Mixer Engine")
        XCTAssertEqual(UAWatchdog.label(connect), "UA Connect")
        XCTAssertEqual(UAWatchdog.label(meter), "UAD Meter")
        XCTAssertEqual(UAWatchdog.label(console), "UAD Console")
        // Anything else: the basename of the whole command, as zsh's `:t` gives it.
        XCTAssertEqual(UAWatchdog.label("/Library/Application Support/Universal Audio/bin/UA Mixer Sentinel"), "UA Mixer Sentinel")
        // Hoes names UA processes the same way.
        XCTAssertEqual(Hoes.name(path: "/x/UA Connect", bundleID: nil, command: connect), "UA Connect")
    }

    func testBuiltInsAreUAOnlyAndNeverSkippedInFront() {
        for r in rules {
            XCTAssertTrue(r.builtIn)
            XCTAssertFalse(r.skipWhenFrontmost)
            XCTAssertEqual(r.action, .kill)
            XCTAssertEqual(r.requiresPath, "/Library/Application Support/Universal Audio")
        }
    }

    // MARK: - Fast path: orphaned helper

    func testOrphanedHelperAtThresholdIsDueAtOnceAndRestartsTheEngine() {
        let r = round(Hoes(), at: 0, [p(32329, ppid: 1, cpu: 80.0, helper)], rules: rules)
        XCTAssertEqual(r.due.map(\.pid), [32329])
        XCTAssertEqual(r.due.first?.ruleID, "ua.helper")
        XCTAssertEqual(r.due.first?.name, "UA Mixer Helper")
        XCTAssertEqual(rule("ua.helper").restart(after: helper), "com.uaudio.ua_mixer_engine")
        XCTAssertEqual(UAWatchdog.killMessage(r.due[0], rule: rule("ua.helper")),
                       "KILLED orphaned UA Mixer Helper pid=32329 cpu=80.0% (fast-path: PPID=1)")
    }

    func testOrphanedHelperBelowFastBarIsLeftAlone() {
        XCTAssertEqual(feed(Hoes(), through: 300, [p(1, ppid: 1, cpu: 79.9, helper)]).due, [])
    }

    func testParentedHelperTakesTheGeneralPathAndStillRestarts() {
        let h = Hoes()
        XCTAssertEqual(feed(h, through: 30, [p(7, ppid: 68313, cpu: 95, helper)]).due, [])
        let r = round(h, at: 60, [p(7, ppid: 68313, cpu: 96, helper)], rules: rules)
        XCTAssertEqual(r.due.map(\.ruleID), ["ua.other"])
        XCTAssertEqual(rule("ua.other").restart(after: helper), "com.uaudio.ua_mixer_engine")   // on the audio path
        XCTAssertEqual(UAWatchdog.killMessage(r.due[0], rule: rule("ua.other")),
                       "KILLED runaway UA Mixer Helper pid=7 cpu=96.0% (>=90% x 3 ticks)")
    }

    // MARK: - Engine: 98 % for 2 minutes

    func testEngineNeedsTwoMinutesAtNinetyEight() {
        let h = Hoes()
        XCTAssertEqual(feed(h, through: 90, [p(1315, cpu: 101.8, engine)]).due, [])
        let r = round(h, at: 120, [p(1315, cpu: 101.0, engine)], rules: rules)
        XCTAssertEqual(r.due.map(\.ruleID), ["ua.engine"])
        XCTAssertEqual(rule("ua.engine").restart(after: engine), "com.uaudio.ua_mixer_engine")
        XCTAssertEqual(UAWatchdog.killMessage(r.due[0], rule: rule("ua.engine")),
                       "KILLED runaway UA Mixer Engine pid=1315 cpu=101.0% (>=98% x 5 ticks)")
    }

    func testEngineBelowNinetyEightIsIgnored() {
        // The whole percent is compared: 97.9 is 97. The general UA rule never applies to the engine.
        XCTAssertEqual(feed(Hoes(), through: 600, [p(1315, cpu: 97.9, engine)]).due, [])
    }

    // MARK: - Everything else: 90 % for 1 minute

    func testOtherUAProcessNeedsAMinuteAtNinetyAndNoRestart() {
        let h = Hoes()
        XCTAssertEqual(feed(h, through: 30, [p(1053, cpu: 90, meter)]).due, [])
        let r = round(h, at: 60, [p(1053, cpu: 100, meter)], rules: rules)
        XCTAssertEqual(r.due.map(\.name), ["UAD Meter"])
        XCTAssertNil(rule("ua.other").restart(after: meter))
    }

    func testNonUAProcessIsNeverTouched() {
        XCTAssertEqual(feed(Hoes(), through: 600, [p(9, ppid: 1, cpu: 100, "/Applications/Safari.app/Contents/MacOS/Safari")]).due, [])
    }

    func testAStreakResetsWhenASampleDrops() {
        let h = Hoes()
        _ = round(h, at: 0, [p(5, cpu: 95, connect)], rules: rules)
        _ = round(h, at: 30, [p(5, cpu: 95, connect)], rules: rules)
        _ = round(h, at: 60, [p(5, cpu: 10, connect)], rules: rules)
        XCTAssertEqual(feed(h, from: 90, through: 120, [p(5, cpu: 95, connect)]).due, [])
        XCTAssertEqual(round(h, at: 150, [p(5, cpu: 95, connect)], rules: rules).due.map(\.pid), [5])
    }

    func testPausedBuiltInsDoNothing() {
        let paused = rules.map { r -> HoeRule in var r = r; r.paused = true; return r }
        XCTAssertEqual(round(Hoes(), at: 0, [p(1, ppid: 1, cpu: 100, helper)], rules: paused).due, [])
    }

    func testNotification() {
        XCTAssertEqual(UAWatchdog.notification(label: "UA Mixer Engine", audioRestored: true, terms: .pimp),
                       "Pimp slapped runaway UA Mixer Engine — audio restored")
        XCTAssertEqual(UAWatchdog.notification(label: "UAD Meter", audioRestored: false, terms: .pimp), "Pimp slapped runaway UAD Meter")
        XCTAssertEqual(UAWatchdog.notification(label: "UA Mixer Engine", audioRestored: true, terms: .normal),
                       "Killed runaway UA Mixer Engine — audio restored")
        XCTAssertEqual(UAWatchdog.notification(label: "UAD Meter", audioRestored: false, terms: .normal), "Killed runaway UAD Meter")
    }

    // MARK: - The old launchd agent

    func testReadsTheAgentsDisabledOverride() {
        let label = "com.nicholassmith.ua-watchdog"
        let text = """
        \tdisabled services = {
        \t\t"com.raycast.macos.RaycastLauncher" => enabled
        \t\t"com.nicholassmith.ua-watchdog" => disabled
        \t}
        """
        XCTAssertTrue(UAWatchdog.isDisabled(label, printDisabled: text))
        XCTAssertTrue(UAWatchdog.isDisabled(label, printDisabled: "\"\(label)\" => true"))
        XCTAssertFalse(UAWatchdog.isDisabled(label, printDisabled: "\"\(label)\" => enabled"))
        XCTAssertFalse(UAWatchdog.isDisabled(label, printDisabled: "\"\(label)\" => false"))
        XCTAssertFalse(UAWatchdog.isDisabled(label, printDisabled: "\"\(label).other\" => disabled"))
        XCTAssertFalse(UAWatchdog.isDisabled(label, printDisabled: ""))
    }
}
