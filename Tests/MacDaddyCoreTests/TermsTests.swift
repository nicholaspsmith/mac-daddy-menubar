// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MacDaddyCore

final class TermsTests: XCTestCase {
    let p = Terms.pimp, n = Terms.normal

    func testForMode() {
        XCTAssertEqual(Terms(.pimp), p)
        XCTAssertEqual(Terms(.normal), n)
    }

    func testModePicker() {
        for t in [p, n] {
            XCTAssertEqual(t.modeMenu, "Mode")
            XCTAssertEqual(t.modeName(.pimp), "Pimp Mode")
            XCTAssertEqual(t.modeName(.normal), "Normal Mode")
        }
    }

    func testLauncher() {
        XCTAssertEqual(p.launcher, "Pimp Cane")
        XCTAssertEqual(n.launcher, "Launcher")
        XCTAssertEqual(n.launcherToggle, "Use the Launcher")
        XCTAssertEqual(p.openLauncher(keys: "⌘Space"), "Open Pimp Cane (⌘Space)")
    }

    func testHoes() {
        XCTAssertEqual(p.hoes, "Hoes")
        XCTAssertEqual(n.hoes, "CPU Hogs")
        XCTAssertEqual(p.hoesTitle(enabled: false, count: 0, suggestions: 0), "Hoes — Off")
        XCTAssertEqual(p.hoesTitle(enabled: true, count: 0, suggestions: 0), "Hoes — none on the clock")
        XCTAssertEqual(p.hoesTitle(enabled: true, count: 2, suggestions: 1), "Hoes — 2 on the clock · 1 suggestion")
        XCTAssertEqual(n.hoesTitle(enabled: false, count: 0, suggestions: 0), "CPU Hogs — Off")
        XCTAssertEqual(n.hoesTitle(enabled: true, count: 0, suggestions: 2), "CPU Hogs — none running hot · 2 suggestions")
        XCTAssertEqual(n.hoesTitle(enabled: true, count: 3, suggestions: 0), "CPU Hogs — 3 running hot")
    }

    func testDownloads() {
        XCTAssertEqual(p.swept, "laundered")
        XCTAssertEqual(n.swept, "swept")
        XCTAssertEqual(p.sweepNow, "Launder Now")
        XCTAssertEqual(n.sweepNow, "Sweep Now")
    }

    func testCrashingOut() {
        XCTAssertEqual(p.crashingOut(2), "⚠ Crashing out (2)")
        XCTAssertEqual(n.crashingOut(2), "⚠ Crash-looping (2)")
        XCTAssertEqual(p.crashingOutTitle(name: "bash"), "bash is crashing out")
        XCTAssertEqual(p.quitting, "Pimp slapping")
        XCTAssertEqual(n.quitting, "Quitting")
    }

    func testTopSpawners() {
        XCTAssertEqual(p.topSpawners, "Welfare Queens")
        XCTAssertEqual(n.topSpawners, "Top Spawners")
        for t in [p, n] {
            XCTAssertEqual(t.children(1), "1 child")
            XCTAssertEqual(t.children(42), "42 children")
        }
    }

    func testEndAndKillNow() {
        XCTAssertEqual(p.end, "Pimp Slap")
        XCTAssertEqual(n.end, "End")
        XCTAssertEqual(p.killNow(count: 3), "Pimp Slap Now (3 this session)")
        XCTAssertEqual(n.killNow(count: 3), "Kill Now (3 this session)")
        XCTAssertEqual(p.trackerTitle(enabled: true, kills: 4), "Federal Agents — 4 pimp slapped")
        XCTAssertEqual(n.trackerTitle(enabled: true, kills: 4), "Media Tracking — 4 killed")
        XCTAssertEqual(n.trackerTitle(enabled: false, kills: 4), "Media Tracking — Off")
        XCTAssertEqual(p.trackerTitle(enabled: false, kills: 4), "Federal Agents — Off")
        XCTAssertEqual(p.restartAfterKill, "Restart After Pimp Slap")
        XCTAssertEqual(n.restartAfterKill, "Restart After Kill")
    }

    func testSuggestions() {
        XCTAssertEqual(p.suggestionPrompt(name: "spin", threshold: 90, minutes: 5), "Auto pimp slap spin? (≥90% for 5 min)")
        XCTAssertEqual(n.suggestionPrompt(name: "spin", threshold: 90, minutes: 5), "Auto-kill spin? (≥90% for 5 min)")
        XCTAssertEqual(p.suggestionNotification(name: "spin", minutes: 10, cpu: 99),
                       "You pimp slapped spin after 10 min at 99% CPU. Pimp slap it automatically next time?")
        XCTAssertEqual(n.suggestionNotification(name: "spin", minutes: 10, cpu: 99),
                       "You ended spin after 10 min at 99% CPU. Auto-kill it next time?")
        XCTAssertEqual(p.tightenedNotification(name: "spin", summary: "≥80% for 2 min"),
                       "You pimp slapped spin again, so its rule now pimp slaps it at ≥80% for 2 min")
        XCTAssertEqual(n.tightenedNotification(name: "spin", summary: "≥80% for 2 min"),
                       "You ended spin again, so its rule now ends it at ≥80% for 2 min")
    }

    func testRuleKills() {
        XCTAssertEqual(p.ruleKill(name: "spin", cpu: 99, minutes: 2), "Pimp slapped runaway spin (99% for 2 min)")
        XCTAssertEqual(n.ruleKill(name: "spin", cpu: 99, minutes: 2), "Ended runaway spin (99% for 2 min)")
        XCTAssertEqual(p.uaKill(label: "UA Mixer Engine", audioRestored: true), "Pimp slapped runaway UA Mixer Engine — audio restored")
        XCTAssertEqual(n.uaKill(label: "UA Mixer Engine", audioRestored: true), "Killed runaway UA Mixer Engine — audio restored")
        XCTAssertEqual(n.uaKill(label: "UAD Meter", audioRestored: false), "Killed runaway UAD Meter")
    }

    func testKillCounts() {
        XCTAssertEqual(p.lastKill(label: "X", ago: "2 h ago"), "Last pimp slap: X, 2 h ago")
        XCTAssertEqual(n.lastKill(label: "X", ago: "2 h ago"), "Last kill: X, 2 h ago")
        XCTAssertEqual(p.killsToday(2), "Pimp slaps today: 2")
        XCTAssertEqual(n.killsToday(2), "Kills today: 2")
        XCTAssertEqual(p.noKillsYet, "No pimp slaps yet")
        XCTAssertEqual(n.noKillsYet, "No kills yet")
    }

    func testRefusalsAndErrors() {
        XCTAssertEqual(p.notAllowed(name: "x", pid: 7), "Not allowed to pimp slap x [7]")
        XCTAssertEqual(n.notAllowed(name: "x", pid: 7), "Not allowed to end x [7]")
        XCTAssertEqual(p.changed(name: "x"), "x changed — not pimp slapped")
        XCTAssertEqual(n.changed(name: "x"), "x changed — not ended")
    }

    func testOrphansAreHoesWithNoPimp() {
        XCTAssertEqual(p.orphanTag, "no pimp")
        XCTAssertEqual(n.orphanTag, "orphaned")
        XCTAssertEqual(p.autoEndOrphans, "Auto Pimp Slap Hoes With No Pimp")
        XCTAssertEqual(n.autoEndOrphans, "Auto-End Orphaned Processes")
        XCTAssertEqual(p.spare, "Spare")
    }

    func testOrphanNotifications() {
        XCTAssertEqual(p.orphanFound, "Hoe with no pimp")
        XCTAssertEqual(n.orphanFound, "Orphaned process")
        XCTAssertEqual(p.orphansFound(3), "3 hoes with no pimp")
        XCTAssertEqual(n.orphansFound(3), "3 orphaned processes")
        XCTAssertEqual(p.orphanBody(name: "x", pid: 7, cpu: 60, minutes: 10), "x (pid 7) has been burning 60% CPU for 10 min with no pimp")
        XCTAssertEqual(n.orphanBody(name: "x", pid: 7, cpu: 60, minutes: 10), "x (pid 7) has been burning 60% CPU for 10 min with no parent")
        XCTAssertEqual(p.orphansBody(["a (60%)", "b (70%)"]), "No pimp and burning CPU: a (60%), b (70%)")
        XCTAssertEqual(n.orphansBody(["a (60%)", "b (70%)"]), "Orphaned and burning CPU: a (60%), b (70%)")
    }

    func testOrphansEndedAutomatically() {
        XCTAssertEqual(p.banished(name: "x", pid: 7, cpu: 60), "Pimp slapped x (pid 7), orphaned, after 30 min at 60% CPU")
        XCTAssertEqual(n.banished(name: "x", pid: 7, cpu: 60), "Ended x (pid 7), orphaned, after 30 min at 60% CPU")
        XCTAssertEqual(p.banishedMany(["a (pid 1)", "b (pid 2)"]), "Pimp slapped orphaned a (pid 1), b (pid 2)")
        XCTAssertEqual(n.banishedMany(["a (pid 1)", "b (pid 2)"]), "Ended orphaned a (pid 1), b (pid 2)")
    }

    func testProcessCount() {
        XCTAssertEqual(p.processCountHigh(count: 2300, limit: 2666, pct: 86),
                       "2300 of 2666 processes (86%). Pimp slap some before fork() starts failing.")
        XCTAssertEqual(n.processCountHigh(count: 2300, limit: 2666, pct: 86),
                       "2300 of 2666 processes (86%). Kill some before fork() starts failing.")
    }

    func testZombies() {
        XCTAssertEqual(p.reapItem(name: "Foo", pid: 7, zombies: 3), "Pimp Slap Foo [7] to reap 3")
        XCTAssertEqual(n.reapItem(name: "Foo", pid: 7, zombies: 3), "Quit Foo [7] to reap 3")
        XCTAssertEqual(p.reapAlertTitle(name: "Foo"), "Pimp slap Foo?")
        XCTAssertEqual(n.reapAlertTitle(name: "Foo"), "Quit Foo?")
        XCTAssertEqual(p.reapAlertButton(name: "Foo"), "Pimp Slap Foo")
        XCTAssertEqual(n.reapAlertButton(name: "Foo"), "Quit Foo")
        XCTAssertEqual(p.notAllowedToQuit(name: "Foo", pid: 7), "Not allowed to pimp slap Foo [7]")
        XCTAssertEqual(n.notAllowedToQuit(name: "Foo", pid: 7), "Not allowed to quit Foo [7]")
    }

    func testProcessWindow() {
        XCTAssertEqual(p.quitButton, "Pimp Slap (SIGTERM)")
        XCTAssertEqual(n.quitButton, "Quit (SIGTERM)")
        XCTAssertEqual(p.forceQuitButton, "Pimp Slap Hard (SIGKILL)")
        XCTAssertEqual(n.forceQuitButton, "Force Quit (SIGKILL)")
        XCTAssertEqual(p.forceQuitAlertTitle(pid: 7), "Pimp slap process 7 hard?")
        XCTAssertEqual(n.forceQuitAlertTitle(pid: 7), "Force quit process 7?")
        XCTAssertEqual(p.forceQuitAlertButton, "Pimp Slap Hard")
        XCTAssertEqual(n.forceQuitAlertButton, "Force Quit")
        XCTAssertEqual(p.signalFailed(pid: 7, signal: "SIGTERM"), "Pimp slap (SIGTERM) on 7 failed")
        XCTAssertEqual(n.signalFailed(pid: 7, signal: "SIGTERM"), "kill(7, SIGTERM) failed")
    }

    func testCoreTextFollowsTheMode() {
        var s = HoesState()
        _ = s.learn(Hoes.ForceQuit(pid: 7, key: "/x/spin", name: "spin", command: "/x/spin", ppid: 500, isApp: false,
                                   meanCPU: 99, hotSeconds: 600, evidence: [], launchdLabel: nil), now: Date())
        let sug = s.suggestions[0]
        XCTAssertEqual(sug.prompt(p), p.suggestionPrompt(name: "spin", threshold: 90, minutes: 5))
        XCTAssertEqual(sug.prompt(n), "Auto-kill spin? (≥90% for 5 min)")
        XCTAssertEqual(sug.notification(n), "You ended spin after 10 min at 99% CPU. Auto-kill it next time?")
        XCTAssertEqual(UAWatchdogLog.summary("", now: Date(), terms: n), ["No kills yet"])
        XCTAssertEqual(UAWatchdogLog.summary("", now: Date(), terms: p), ["No pimp slaps yet"])
    }

    // MARK: - Mode setting

    func defaults() -> (UserDefaults, String) {
        let suite = "MacDaddyTests.mode.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    func testModeDefaultsToPimp() {
        let (d, suite) = defaults(); defer { d.removePersistentDomain(forName: suite) }
        XCTAssertEqual(Mode.load(from: d), .pimp)
        Mode.normal.save(to: d)
        XCTAssertEqual(Mode.load(from: d), .normal)
        XCTAssertEqual(d.string(forKey: "mode"), "normal")
    }

    func testPlainSymbolIconMigratesToNormalMode() {
        let (d, suite) = defaults(); defer { d.removePersistentDomain(forName: suite) }
        d.set("symbol", forKey: "iconStyle")
        Mode.migrateIconStyle(in: d)
        XCTAssertEqual(Mode.load(from: d), .normal)
        XCTAssertNil(d.object(forKey: "iconStyle"))
    }

    func testCharacterIconMigratesToPimpMode() {
        let (d, suite) = defaults(); defer { d.removePersistentDomain(forName: suite) }
        d.set("character", forKey: "iconStyle")
        Mode.migrateIconStyle(in: d)
        XCTAssertEqual(Mode.load(from: d), .pimp)
        XCTAssertNil(d.object(forKey: "iconStyle"))
    }

    func testMigrationNeverOverridesAChosenMode() {
        let (d, suite) = defaults(); defer { d.removePersistentDomain(forName: suite) }
        Mode.pimp.save(to: d)
        d.set("symbol", forKey: "iconStyle")
        Mode.migrateIconStyle(in: d)
        XCTAssertEqual(Mode.load(from: d), .pimp)
        XCTAssertNil(d.object(forKey: "iconStyle"))
        Mode.migrateIconStyle(in: d)   // nothing to do
        XCTAssertEqual(Mode.load(from: d), .pimp)
    }
}
