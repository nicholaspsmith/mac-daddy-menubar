// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import StatusItemKit

/// SIGKILLs headless Godot runs that hung. Was the godot-headless-reaper agent.
final class Reaper: NSObject, Duty {
    var onSweep: ((Flourish) -> Void)?
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let every: TimeInterval = 300
    private var lastRun = Date.distantPast
    private var lastError: String?
    private(set) var reapedThisSession = 0

    var enabled: Bool {
        get { defaults.object(forKey: "reaper.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "reaper.enabled"); onChange?() }
    }
    var thresholdSeconds: Int {
        let v = defaults.integer(forKey: "reaper.thresholdSeconds"); return v > 0 ? v : 900
    }

    func tick(now: Date) {
        if enabled && now.timeIntervalSince(lastRun) >= every { reap(now: now) }
    }

    private func reap(now: Date) {
        lastRun = now
        guard let ps = Shell.run("/bin/ps", ["-Axo", "pid=,etime=,command="]) else {
            lastError = "Couldn't list processes"; return
        }
        lastError = nil
        var killed = 0
        for pid in ReapRule.pidsToReap(psOutput: ps, thresholdSeconds: thresholdSeconds) {
            if kill(pid_t(pid), SIGKILL) == 0 { killed += 1 }
            else if errno == EPERM { lastError = "Not allowed to stop pid \(pid)" }
            // ESRCH: already gone — not an error.
        }
        if killed > 0 { reapedThisSession += killed; onSweep?(.hatTip) }
    }

    func addMenuItems(to menu: NSMenu) {
        heading("Godot Reaper", error: lastError).forEach(menu.addItem)
        let toggle = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self; toggle.state = enabled ? .on : .off
        menu.addItem(indented(toggle))
        let now = NSMenuItem(title: "Reap Now (\(reapedThisSession) this session)", action: #selector(reapNow), keyEquivalent: "")
        now.target = self
        menu.addItem(indented(now))
    }

    @objc private func toggleEnabled() { enabled.toggle() }
    @objc private func reapNow() { reap(now: Date()) }
}
