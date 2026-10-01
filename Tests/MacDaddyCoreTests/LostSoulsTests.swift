// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MacDaddyCore

final class LostSoulsTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let allow = LostSouls.defaultAllowlist

    /// One `ps -o pid=,ppid=,%cpu=,etime=,comm=` line. `startedAgo` is the
    /// process's age at `t0`; `at` is seconds after `t0`.
    func line(_ pid: Int, ppid: Int = 1, cpu: Double, startedAgo: Int = 3600, at: Int,
              comm: String = "/opt/tools/busy loop") -> String {
        let age = startedAgo + at
        let etime = String(format: "%02d:%02d:%02d", age / 3600, (age / 60) % 60, age % 60)
        return "  \(pid)  \(ppid)  \(cpu) \(etime) \(comm)"
    }

    /// Samples every 30 s from 0 through `minutes` minutes.
    func feed(_ souls: LostSouls, minutes: Int, _ lines: (Int) -> [String]) {
        for at in stride(from: 0, through: minutes * 60, by: 30) {
            souls.record(snapshot: lines(at).joined(separator: "\n"), at: t0.addingTimeInterval(Double(at)))
        }
    }

    func qualifying(_ s: LostSouls, at: Int, launchd: Set<Int> = [], isApp: @escaping (Int, String) -> Bool = { _, _ in false }) -> [LostSouls.Soul] {
        s.qualifying(now: t0.addingTimeInterval(Double(at)), allowlist: allow, launchdPIDs: launchd, isApp: isApp)
    }

    func testOrphanedHotAndLongQualifies() {
        let s = LostSouls()
        feed(s, minutes: 10) { [line(4242, cpu: 99.5, at: $0)] }
        let q = qualifying(s, at: 600)
        XCTAssertEqual(q.map(\.pid), [4242])
        XCTAssertEqual(q.first?.name, "busy loop")
        XCTAssertEqual(q.first?.meanCPU ?? 0, 99.5, accuracy: 0.01)
        XCTAssertEqual(q.first?.minutes, 10)
        XCTAssertEqual(q.first?.isNew, true)
        XCTAssertEqual(qualifying(s, at: 600).first?.isNew, false)   // notified once
    }

    func testNotOrphanedNeverQualifies() {
        let s = LostSouls()
        feed(s, minutes: 12) { [line(10, ppid: 900, cpu: 99, at: $0)] }
        XCTAssertTrue(qualifying(s, at: 720).isEmpty)
    }

    func testHotButUnderTenMinutesDoesNotQualify() {
        let s = LostSouls()
        feed(s, minutes: 9) { [line(11, cpu: 99, at: $0)] }
        XCTAssertTrue(qualifying(s, at: 540).isEmpty)
    }

    func testMeanAtOrBelowFiftyDoesNotQualify() {
        let s = LostSouls()
        feed(s, minutes: 12) { at in [line(12, cpu: 50, at: at), line(13, cpu: at % 60 == 0 ? 90 : 4, at: at)] }
        XCTAssertTrue(qualifying(s, at: 720).isEmpty)
    }

    func testOnlyTheLastTenMinutesCount() {
        let s = LostSouls()
        // Hot for the first 10 minutes, then idle for the next 12: the window has cooled.
        feed(s, minutes: 22) { [line(14, cpu: $0 <= 600 ? 99 : 0.5, at: $0)] }
        XCTAssertTrue(qualifying(s, at: 1320).isEmpty)
    }

    func testAllowlistedLaunchdJobsAndAppsAreExcluded() {
        let s = LostSouls()
        feed(s, minutes: 10) { at in [
            line(20, cpu: 99, at: at, comm: "/usr/sbin/distnoted"),
            line(21, cpu: 99, at: at, comm: "/usr/local/bin/ollama"),
            line(22, cpu: 99, at: at, comm: "/usr/libexec/somejob"),
            line(23, cpu: 99, at: at, comm: "/Applications/Chat.app/Contents/MacOS/Chat"),
            line(24, cpu: 99, at: at, comm: "/Applications/Godot.app/Contents/MacOS/Godot"),
            line(25, cpu: 99, at: at, comm: "-zsh"),
        ] }
        let q = qualifying(s, at: 600, launchd: [22], isApp: { pid, _ in pid == 23 })
        XCTAssertEqual(q.map(\.pid), [24, 25])   // headless Godot has no app entry, so it counts
    }

    func testSparedUntilItExitsAndAReusedPIDIsNotSpared() {
        let s = LostSouls()
        feed(s, minutes: 10) { [line(30, cpu: 99, at: $0)] }
        s.spare(pid: 30)
        XCTAssertTrue(qualifying(s, at: 600).isEmpty)
        s.record(snapshot: line(30, cpu: 99, at: 630), at: t0.addingTimeInterval(630))
        XCTAssertTrue(qualifying(s, at: 630).isEmpty)
        // pid 30 is reused by a new process (started just now): tracked afresh, not spared.
        for at in stride(from: 660, through: 1260, by: 30) {
            s.record(snapshot: line(30, cpu: 99, startedAgo: -660, at: at), at: t0.addingTimeInterval(Double(at)))
        }
        let q = qualifying(s, at: 1260)
        XCTAssertEqual(q.map(\.pid), [30])
        XCTAssertEqual(q.first?.isNew, true)
    }

    func testAReusedPIDStartsItsWindowOver() {
        let s = LostSouls()
        feed(s, minutes: 9) { [line(31, cpu: 99, at: $0)] }
        // A different program now holds pid 31; one more minute is not ten.
        s.record(snapshot: line(31, cpu: 99, at: 600, comm: "/bin/other"), at: t0.addingTimeInterval(600))
        XCTAssertTrue(qualifying(s, at: 600).isEmpty)
    }

    func testExitedPIDsArePruned() {
        let s = LostSouls()
        feed(s, minutes: 10) { [line(40, cpu: 99, at: $0), line(41, cpu: 99, at: $0)] }
        XCTAssertEqual(s.trackedPIDs, [40, 41])
        s.record(snapshot: line(41, cpu: 99, at: 630), at: t0.addingTimeInterval(630))
        XCTAssertEqual(s.trackedPIDs, [41])
    }

    func testQualifiedSinceTracksHowLongItHasQualified() {
        let s = LostSouls()
        feed(s, minutes: 10) { [line(45, cpu: 99, at: $0)] }
        XCTAssertEqual(qualifying(s, at: 600).first?.qualifiedSince, t0.addingTimeInterval(600))
        s.record(snapshot: line(45, cpu: 99, at: 630), at: t0.addingTimeInterval(630))
        XCTAssertEqual(qualifying(s, at: 630).first?.qualifiedSince, t0.addingTimeInterval(600))
    }

    func testMalformedLinesAreIgnored() {
        let s = LostSouls()
        let junk = ["", "  PID PPID %CPU ELAPSED COMM", "abc 1 99 01:00 /bin/x", "50 1 hot 01:00 /bin/x",
                    "51 1 99 nope /bin/x", "52 1 99 01:00", "  7"]
        feed(s, minutes: 10) { junk + [self.line(60, cpu: 99, at: $0)] }
        XCTAssertEqual(s.trackedPIDs, [60])
        XCTAssertEqual(qualifying(s, at: 600).map(\.pid), [60])
    }

    func testElapsedParsesEveryPsForm() {
        XCTAssertEqual(LostSouls.elapsedSeconds("00:59"), 59)
        XCTAssertEqual(LostSouls.elapsedSeconds("15:00"), 900)
        XCTAssertEqual(LostSouls.elapsedSeconds("01:02:03"), 3723)
        XCTAssertEqual(LostSouls.elapsedSeconds("2-00:00:01"), 172_801)
        XCTAssertNil(LostSouls.elapsedSeconds(""))
        XCTAssertNil(LostSouls.elapsedSeconds("ab:cd"))
    }

    func testLaunchctlListPIDs() {
        let text = "PID\tStatus\tLabel\n-\t0\tcom.apple.idle\n1093\t0\tcom.apple.progressd\n77\t-9\tcom.example.job\n\nbad line\n"
        XCTAssertEqual(LostSouls.launchdPIDs(fromLaunchctlList: text), [1093, 77])
    }
}
