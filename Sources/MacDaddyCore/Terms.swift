// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// Pimp Mode (the default: Menu Pimp himself and his nomenclature) or Normal
/// Mode (a plain symbol and standard terms).
public enum Mode: String, CaseIterable {
    case pimp, normal

    public static let key = "mode"
    private static let iconStyleKey = "iconStyle"

    public static func load(from d: UserDefaults) -> Mode { d.string(forKey: key).flatMap(Mode.init) ?? .pimp }
    public func save(to d: UserDefaults) { d.set(rawValue, forKey: Self.key) }

    /// The old Icon picker becomes the mode, once: the plain symbol meant
    /// Normal Mode. A mode already chosen wins. The old key is removed.
    public static func migrateIconStyle(in d: UserDefaults) {
        guard let style = d.string(forKey: iconStyleKey) else { return }
        if d.string(forKey: key) == nil { (style == "symbol" ? Mode.normal : .pimp).save(to: d) }
        d.removeObject(forKey: iconStyleKey)
    }
}

/// Every user-facing string that differs by mode. Log lines, defaults keys and
/// code keep their own names whatever the mode.
public struct Terms: Equatable {
    public let mode: Mode
    public init(_ mode: Mode) { self.mode = mode }
    public static let pimp = Terms(.pimp), normal = Terms(.normal)

    private var pimp: Bool { mode == .pimp }
    private func pick(_ p: String, _ n: String) -> String { pimp ? p : n }

    // MARK: Mode picker

    public var modeMenu: String { "Mode" }
    public func modeName(_ m: Mode) -> String { m == .pimp ? "Pimp Mode" : "Normal Mode" }

    // MARK: Launcher (formerly Menu Crane)

    public var launcher: String { pick("Pimp Cane", "Launcher") }
    public var launcherToggle: String { "Use the \(launcher)" }
    public func openLauncher(keys: String) -> String { "Open \(launcher) (\(keys))" }

    // MARK: Hoes (CPU Hogs)

    public var hoes: String { pick("Hoes", "CPU Hogs") }
    public func hoesTitle(enabled: Bool, count: Int, suggestions: Int) -> String {
        guard enabled else { return "\(hoes) — Off" }
        let hot = pick("on the clock", "running hot")
        var t = count == 0 ? "\(hoes) — none \(hot)" : "\(hoes) — \(count) \(hot)"
        if suggestions > 0 { t += " · \(suggestions) suggestion\(suggestions == 1 ? "" : "s")" }
        return t
    }
    public var restartAfterKill: String { pick("Restart After Pimp Slap", "Restart After Kill") }
    public func suggestionPrompt(name: String, threshold: Int, minutes: Int) -> String {
        pick("Auto pimp slap", "Auto-kill") + " \(name)? (≥\(threshold)% for \(minutes) min)"
    }
    public func suggestionNotification(name: String, minutes: Int, cpu: Int) -> String {
        pick("You pimp slapped \(name) after \(minutes) min at \(cpu)% CPU. Pimp slap it automatically next time?",
             "You ended \(name) after \(minutes) min at \(cpu)% CPU. Auto-kill it next time?")
    }
    public func tightenedNotification(name: String, summary: String) -> String {
        pick("You pimp slapped \(name) again, so its rule now pimp slaps it at \(summary)",
             "You ended \(name) again, so its rule now ends it at \(summary)")
    }
    public func ruleKill(name: String, cpu: Int, minutes: Int) -> String {
        pick("Pimp slapped", "Ended") + " runaway \(name) (\(cpu)% for \(minutes) min)"
    }
    public func uaKill(label: String, audioRestored: Bool) -> String {
        pick("Pimp slapped", "Killed") + " runaway \(label)" + (audioRestored ? " — audio restored" : "")
    }
    public func lastKill(label: String, ago: String) -> String { pick("Last pimp slap", "Last kill") + ": \(label), \(ago)" }
    public func killsToday(_ n: Int) -> String { pick("Pimp slaps today", "Kills today") + ": \(n)" }
    public var noKillsYet: String { pick("No pimp slaps yet", "No kills yet") }

    // MARK: Ending things

    public var end: String { pick("Pimp Slap", "End") }
    public func notAllowed(name: String, pid: Int) -> String { pick("Not allowed to pimp slap", "Not allowed to end") + " \(name) [\(pid)]" }
    public func changed(name: String) -> String { "\(name) changed — not " + pick("pimp slapped", "ended") }

    // MARK: Hoes with no pimp (orphaned processes; Street Walkers until 1.18.0)

    /// The tag on an orphan's row in Hoes.
    public var orphanTag: String { pick("no pimp", "orphaned") }
    public var autoEndOrphans: String { pick("Auto Pimp Slap Hoes With No Pimp", "Auto-End Orphaned Processes") }
    public var spare: String { "Spare" }
    public var orphanFound: String { pick("Hoe with no pimp", "Orphaned process") }
    public func orphansFound(_ n: Int) -> String { "\(n) " + pick("hoes with no pimp", "orphaned processes") }
    public func orphanBody(name: String, pid: Int, cpu: Int, minutes: Int) -> String {
        "\(name) (pid \(pid)) has been burning \(cpu)% CPU for \(minutes) min with no " + pick("pimp", "parent")
    }
    public func orphansBody(_ items: [String]) -> String {
        pick("No pimp", "Orphaned") + " and burning CPU: " + items.joined(separator: ", ")
    }
    public func banished(name: String, pid: Int, cpu: Int) -> String {
        pick("Pimp slapped", "Ended") + " \(name) (pid \(pid)), orphaned, after 30 min at \(cpu)% CPU"
    }
    public func banishedMany(_ items: [String]) -> String { pick("Pimp slapped", "Ended") + " orphaned " + items.joined(separator: ", ") }

    // MARK: Downloads

    public var swept: String { pick("laundered", "swept") }
    public var sweepNow: String { pick("Launder Now", "Sweep Now") }

    // MARK: Media Tracking

    public func trackerTitle(enabled: Bool, kills: Int) -> String {
        let name = pick("Federal Agents", "Media Tracking")
        return enabled ? "\(name) — \(kills) " + pick("pimp slapped", "killed") : "\(name) — Off"
    }
    public func killNow(count: Int) -> String { pick("Pimp Slap Now", "Kill Now") + " (\(count) this session)" }

    // MARK: Processes

    public func crashingOut(_ n: Int) -> String { "⚠ " + pick("Crashing out", "Crash-looping") + " (\(n))" }
    public var quitting: String { pick("Pimp slapping", "Quitting") }
    public func crashingOutTitle(name: String) -> String { "\(name) is " + pick("crashing out", "crash-looping") }
    public var topSpawners: String { pick("Welfare Queens", "Top Spawners") }
    /// A spawner's brood, grandchildren included: "1 child", "42 children".
    public func children(_ n: Int) -> String { n == 1 ? "1 child" : "\(n) children" }
    public func processCountHigh(count: Int, limit: Int, pct: Int) -> String {
        "\(count) of \(limit) processes (\(pct)%). " + pick("Pimp slap", "Kill") + " some before fork() starts failing."
    }
    public func reapItem(name: String, pid: Int, zombies: Int) -> String { pick("Pimp Slap", "Quit") + " \(name) [\(pid)] to reap \(zombies)" }
    public func reapAlertTitle(name: String) -> String { pick("Pimp slap", "Quit") + " \(name)?" }
    public func reapAlertButton(name: String) -> String { pick("Pimp Slap", "Quit") + " \(name)" }
    public func notAllowedToQuit(name: String, pid: Int) -> String { pick("Not allowed to pimp slap", "Not allowed to quit") + " \(name) [\(pid)]" }

    // MARK: Process window

    public var quitButton: String { pick("Pimp Slap (SIGTERM)", "Quit (SIGTERM)") }
    public var forceQuitButton: String { pick("Pimp Slap Hard (SIGKILL)", "Force Quit (SIGKILL)") }
    public func forceQuitAlertTitle(pid: Int) -> String { pick("Pimp slap process \(pid) hard?", "Force quit process \(pid)?") }
    public var forceQuitAlertButton: String { pick("Pimp Slap Hard", "Force Quit") }
    public func signalFailed(pid: Int, signal: String) -> String { pick("Pimp slap (\(signal)) on \(pid) failed", "kill(\(pid), \(signal)) failed") }
}
