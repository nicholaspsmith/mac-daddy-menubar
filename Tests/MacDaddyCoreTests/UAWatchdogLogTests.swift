// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MacDaddyCore

final class UAWatchdogLogTests: XCTestCase {
    /// A Date from a log-style stamp, parsed the way the log is, so
    /// `killsToday` (which uses Calendar.current) is time-zone independent.
    private func date(_ stamp: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = UAWatchdogLog.dateFormat
        return f.date(from: stamp)!
    }

    func testParsesKilledOrphanedHelper() {
        let e = UAWatchdogLog.parseLine(
            "2026-07-30 16:16:07  KILLED orphaned UA Mixer Helper pid=32329 cpu=100.0% (fast-path: PPID=1)")
        XCTAssertEqual(e?.kind, .killed)
        XCTAssertEqual(e?.label, "UA Mixer Helper")
    }

    func testParsesKilledRunawayLabel() {
        let e = UAWatchdogLog.parseLine(
            "2026-07-30 16:16:20  KILLED runaway UA Mixer Sentinel pid=32331 cpu=100.0% (>=90% x 2 ticks)")
        XCTAssertEqual(e?.kind, .killed)
        XCTAssertEqual(e?.label, "UA Mixer Sentinel")
    }

    func testParsesWarn() {
        let e = UAWatchdogLog.parseLine("2026-07-30 16:16:07  WARN UA Mixer Sentinel pid=32331 cpu=100.0% (tick 1/2 >=90%)")
        XCTAssertEqual(e?.kind, .warn)
        XCTAssertEqual(e?.label, "UA Mixer Sentinel")
    }

    func testKickstartLineIsOther() {
        let e = UAWatchdogLog.parseLine("2026-07-30 16:16:07  kickstarted UA mixer engine to restore audio path")
        XCTAssertEqual(e?.kind, .other)
        XCTAssertEqual(e?.label, "")
    }

    func testNonTimestampedLinesAreNil() {
        XCTAssertNil(UAWatchdogLog.parseLine(""))
        XCTAssertNil(UAWatchdogLog.parseLine("===== rekordbox aggregate removal ====="))
        XCTAssertNil(UAWatchdogLog.parseLine("short"))
    }

    private let sampleLog = """
    2026-08-01 09:00:00  WARN UA Mixer Sentinel pid=100 cpu=95.0% (tick 1/2 >=90%)
    2026-08-01 09:01:00  KILLED runaway UA Mixer Sentinel pid=100 cpu=100.0% (>=90% x 2 ticks)
    2026-08-01 09:02:00  KILLED orphaned UA Mixer Helper pid=200 cpu=100.0% (fast-path: PPID=1)
    2026-08-01 09:02:00  kickstarted UA mixer engine to restore audio path
    2026-07-31 23:59:00  KILLED runaway UAD Meter pid=300 cpu=99.0% (>=90% x 2 ticks)
    """

    func testLastKillIsTheMostRecentKilledLine() {
        let last = UAWatchdogLog.lastKill(sampleLog)
        XCTAssertEqual(last?.label, "UA Mixer Helper")
        XCTAssertEqual(last?.date, date("2026-08-01 09:02:00"))
    }

    func testKillsTodayCountsOnlyTodaysKills() {
        // Two kills on 08-01, one on 07-31; the WARN and the kickstart don't count.
        XCTAssertEqual(UAWatchdogLog.killsToday(sampleLog, now: date("2026-08-01 12:00:00")), 2)
        XCTAssertEqual(UAWatchdogLog.killsToday(sampleLog, now: date("2026-07-31 12:00:00")), 1)
    }

    func testLastKillNilWhenNeverKilled() {
        let onlyWarns = "2026-08-01 09:00:00  WARN UA Connect pid=1 cpu=95.0% (tick 1/2 >=90%)"
        XCTAssertNil(UAWatchdogLog.lastKill(onlyWarns))
        XCTAssertEqual(UAWatchdogLog.killsToday(onlyWarns, now: date("2026-08-01 10:00:00")), 0)
    }

    func testWrittenLinesMatchTheScriptsFormatAndParseBack() {
        let at = date("2026-09-30 10:29:30")
        let text = UAWatchdogLog.line("KILLED runaway UA Mixer Engine pid=1315 cpu=101.0% (>=98% x 3 ticks)", at: at)
        XCTAssertEqual(text, "2026-09-30 10:29:30  KILLED runaway UA Mixer Engine pid=1315 cpu=101.0% (>=98% x 3 ticks)\n")
        XCTAssertEqual(UAWatchdogLog.lastKill(text)?.label, "UA Mixer Engine")
        XCTAssertEqual(UAWatchdogLog.lastKill(text)?.date, at)
    }

    func testAgo() {
        XCTAssertEqual(UAWatchdogLog.ago(0), "just now")
        XCTAssertEqual(UAWatchdogLog.ago(59), "just now")
        XCTAssertEqual(UAWatchdogLog.ago(60), "1 min ago")
        XCTAssertEqual(UAWatchdogLog.ago(3599), "59 min ago")
        XCTAssertEqual(UAWatchdogLog.ago(2 * 3600 + 1800), "2 h ago")
        XCTAssertEqual(UAWatchdogLog.ago(47 * 3600), "47 h ago")
        XCTAssertEqual(UAWatchdogLog.ago(3 * 86400), "3 d ago")
        XCTAssertEqual(UAWatchdogLog.ago(-5), "just now")   // clock moved back
    }

    func testSummary() {
        let now = date("2026-08-01 11:02:00")
        XCTAssertEqual(UAWatchdogLog.summary(sampleLog, now: now),
                       ["Last pimp slap: UA Mixer Helper, 2 h ago", "Pimp slaps today: 2"])
        XCTAssertEqual(UAWatchdogLog.summary("", now: now), ["No pimp slaps yet"])
    }
}
