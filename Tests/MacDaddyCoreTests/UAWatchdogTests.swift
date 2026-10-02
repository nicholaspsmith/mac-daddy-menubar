// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MacDaddyCore

final class UAWatchdogTests: XCTestCase {
    let helper = "/Applications/Universal Audio/UAD Console.app/Contents/Helpers/UA Mixer Helper.app/Contents/MacOS/UA Mixer Helper"
    let engine = "/Library/Application Support/Universal Audio/Apollo/UA Mixer Engine.app/Contents/MacOS/UA Mixer Engine -silent"
    let connect = "/Applications/UA Connect.app/Contents/MacOS/UA Connect --no-window"
    let meter = "/Applications/Universal Audio/UAD Meter & Control Panel.app/Contents/MacOS/UAD Meter & Control Panel -h"
    let console = "/Applications/Universal Audio/UAD Console.app/Contents/MacOS/UAD Console"

    /// One `ps -Ao pid=,ppid=,pcpu=,command= -ww` line.
    func line(_ pid: Int, ppid: Int = 500, cpu: String, _ command: String) -> String {
        "  \(pid)  \(ppid)  \(cpu) \(command)"
    }

    func scan(_ w: inout UAWatchdog, _ lines: String...) -> UAWatchdog.Scan {
        w.scan(ps: lines.joined(separator: "\n"))
    }

    // MARK: - Which processes, and what they are called

    func testOnlyUAProcessesCount() {
        XCTAssertTrue(UAWatchdog.isUA(helper))
        XCTAssertTrue(UAWatchdog.isUA(connect))
        XCTAssertTrue(UAWatchdog.isUA("/opt/x/UA Mixer Sentinel"))
        XCTAssertFalse(UAWatchdog.isUA("/Applications/Safari.app/Contents/MacOS/Safari"))
        XCTAssertFalse(UAWatchdog.isUA("/usr/sbin/coreaudiod"))
    }

    func testLabelsAndRoles() {
        XCTAssertEqual(UAWatchdog.classify(helper).label, "UA Mixer Helper")
        XCTAssertEqual(UAWatchdog.classify(helper).role, .helper)
        XCTAssertEqual(UAWatchdog.classify(engine).label, "UA Mixer Engine")
        XCTAssertEqual(UAWatchdog.classify(engine).role, .engine)
        XCTAssertEqual(UAWatchdog.classify(connect).label, "UA Connect")
        XCTAssertEqual(UAWatchdog.classify(connect).role, .other)
        XCTAssertEqual(UAWatchdog.classify(meter).label, "UAD Meter")
        XCTAssertEqual(UAWatchdog.classify(console).label, "UAD Console")
        // Anything else: the basename of the whole command, as zsh's `:t` gives it.
        XCTAssertEqual(UAWatchdog.classify("/Library/Application Support/Universal Audio/bin/UA Mixer Sentinel").label,
                       "UA Mixer Sentinel")
        XCTAssertEqual(UAWatchdog.classify("/Library/Application Support/Universal Audio/bin/UA Mixer Sentinel").role, .other)
    }

    func testParsesPsKeepingTheCommandWhole() {
        let procs = UAWatchdog.parse(ps: line(952, ppid: 1, cpu: "8.3", engine) + "\n\ngarbage\n")
        XCTAssertEqual(procs, [UAWatchdog.Proc(pid: 952, ppid: 1, cpu: "8.3", command: engine)])
    }

    // MARK: - Fast path: orphaned helper

    func testOrphanedHelperAtThresholdIsKilledAtOnce() {
        var w = UAWatchdog()
        let s = scan(&w, line(32329, ppid: 1, cpu: "80.0", helper))
        XCTAssertEqual(s.kills, [UAWatchdog.Kill(pid: 32329, label: "UA Mixer Helper")])
        XCTAssertTrue(s.audioPathHit)
        XCTAssertEqual(s.messages, ["KILLED orphaned UA Mixer Helper pid=32329 cpu=80.0% (fast-path: PPID=1)"])
        XCTAssertEqual(s.notification, "Killed runaway UA Mixer Helper — audio restored")
    }

    func testOrphanedHelperBelowFastBarIsLeftAlone() {
        var w = UAWatchdog()
        let s = scan(&w, line(1, ppid: 1, cpu: "79.9", helper))
        XCTAssertEqual(s, UAWatchdog.Scan())
        XCTAssertNil(s.notification)
    }

    func testParentedHelperTakesTheGeneralPath() {
        var w = UAWatchdog()
        let first = scan(&w, line(7, ppid: 68313, cpu: "95.0", helper))
        XCTAssertEqual(first.kills, [])
        XCTAssertEqual(first.messages, ["WARN UA Mixer Helper pid=7 cpu=95.0% (tick 1/2 >=90%)"])
        let second = scan(&w, line(7, ppid: 68313, cpu: "96.0", helper))
        XCTAssertEqual(second.kills, [UAWatchdog.Kill(pid: 7, label: "UA Mixer Helper")])
        XCTAssertTrue(second.audioPathHit)   // a helper is on the audio path either way
    }

    // MARK: - Engine: 98 % across 3 ticks

    func testEngineNeedsThreeTicksAtNinetyEight() {
        var w = UAWatchdog()
        XCTAssertEqual(scan(&w, line(1315, cpu: "101.8", engine)).messages,
                       ["WARN UA Mixer Engine pid=1315 cpu=101.8% (tick 1/3 >=98%)"])
        XCTAssertEqual(scan(&w, line(1315, cpu: "103.2", engine)).messages,
                       ["WARN UA Mixer Engine pid=1315 cpu=103.2% (tick 2/3 >=98%)"])
        let s = scan(&w, line(1315, cpu: "101.0", engine))
        XCTAssertEqual(s.messages, ["KILLED runaway UA Mixer Engine pid=1315 cpu=101.0% (>=98% x 3 ticks)"])
        XCTAssertEqual(s.kills, [UAWatchdog.Kill(pid: 1315, label: "UA Mixer Engine")])
        XCTAssertTrue(s.audioPathHit)
        XCTAssertEqual(s.notification, "Killed runaway UA Mixer Engine — audio restored")
    }

    func testEngineBelowNinetyEightIsIgnored() {
        // The script compares the integer part: 97.9 is 97.
        var w = UAWatchdog()
        for _ in 0..<5 { XCTAssertEqual(scan(&w, line(1315, cpu: "97.9", engine)), UAWatchdog.Scan()) }
    }

    // MARK: - Everything else: 90 % across 2 ticks

    func testOtherUAProcessNeedsTwoTicksAtNinety() {
        var w = UAWatchdog()
        XCTAssertEqual(scan(&w, line(1053, cpu: "90.0", meter)).messages,
                       ["WARN UAD Meter pid=1053 cpu=90.0% (tick 1/2 >=90%)"])
        let s = scan(&w, line(1053, cpu: "100.0", meter))
        XCTAssertEqual(s.messages, ["KILLED runaway UAD Meter pid=1053 cpu=100.0% (>=90% x 2 ticks)"])
        XCTAssertFalse(s.audioPathHit)
        XCTAssertEqual(s.notification, "Killed runaway UAD Meter")
    }

    func testNonUAProcessIsNeverTouched() {
        var w = UAWatchdog()
        for _ in 0..<3 {
            XCTAssertEqual(scan(&w, line(9, ppid: 1, cpu: "100.0", "/Applications/Safari.app/Contents/MacOS/Safari")),
                           UAWatchdog.Scan())
        }
    }

    // MARK: - Counting

    func testCountResetsWhenASampleDrops() {
        var w = UAWatchdog()
        _ = scan(&w, line(5, cpu: "95.0", connect))
        _ = scan(&w, line(5, cpu: "10.0", connect))
        XCTAssertEqual(w.pending, [:])
        let s = scan(&w, line(5, cpu: "95.0", connect))
        XCTAssertEqual(s.kills, [])
        XCTAssertEqual(s.messages, ["WARN UA Connect pid=5 cpu=95.0% (tick 1/2 >=90%)"])
    }

    func testCountsArePerPID() {
        var w = UAWatchdog()
        _ = scan(&w, line(5, cpu: "95.0", connect))
        let s = scan(&w, line(6, cpu: "95.0", connect))   // pid 5 is gone; 6 starts over
        XCTAssertEqual(s.kills, [])
        XCTAssertEqual(w.pending, [6: 1])
    }

    func testAKillClearsTheCount() {
        var w = UAWatchdog()
        _ = scan(&w, line(5, cpu: "95.0", connect))
        _ = scan(&w, line(5, cpu: "95.0", connect))
        XCTAssertEqual(w.pending, [:])
    }

    func testResetForgetsPendingCounts() {
        var w = UAWatchdog()
        _ = scan(&w, line(5, cpu: "95.0", connect))
        w.reset()
        XCTAssertEqual(scan(&w, line(5, cpu: "95.0", connect)).kills, [])
    }

    func testNotificationNamesTheFirstKillAndAudioPathWins() {
        var w = UAWatchdog()
        _ = scan(&w, line(5, cpu: "95.0", meter))
        let s = scan(&w, line(5, cpu: "95.0", meter), line(6, ppid: 1, cpu: "99.0", helper))
        XCTAssertEqual(s.kills.map(\.label), ["UAD Meter", "UA Mixer Helper"])
        XCTAssertTrue(s.audioPathHit)
        XCTAssertEqual(s.notification, "Killed runaway UAD Meter — audio restored")
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
