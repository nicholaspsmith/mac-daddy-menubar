// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import os
import StatusItemKit

private let log = Logger(subsystem: "com.nicholaspsmith.MacDaddy", category: "lostSouls")

/// Finds your own orphaned processes that have burned CPU for ten minutes and
/// offers to end them. Never kills on its own unless Banish automatically is on.
/// Replaced the Godot-only reaper.
final class LostSoulsDuty: NSObject, Duty {
    var onSweep: ((Flourish) -> Void)?
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let notifier: Notifier
    private let sampleSeconds: TimeInterval = 30
    private let autoBanishAfter: TimeInterval = 30 * 60
    private let souls = LostSouls()
    private let queue = DispatchQueue(label: "macdaddy.lostsouls")
    private var inFlight = false
    private var lastSample = Date.distantPast
    private var lastError: String?
    private(set) var current: [LostSouls.Soul] = []

    init(notifier: Notifier) { self.notifier = notifier }

    var enabled: Bool {
        get { defaults.object(forKey: "lostSouls.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "lostSouls.enabled"); if !newValue { current = [] }; onChange?() }
    }
    var autoBanish: Bool {
        get { defaults.object(forKey: "lostSouls.autoBanish") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "lostSouls.autoBanish") }
    }

    func tick(now: Date) {
        guard enabled, !inFlight, now.timeIntervalSince(lastSample) >= sampleSeconds - 0.5 else { return }
        lastSample = now
        inFlight = true
        let uid = String(getuid())
        queue.async { [weak self] in
            let ps = Shell.run("/bin/ps", ["-U", uid, "-o", "pid=,ppid=,%cpu=,etime=,comm=", "-ww"])
            let jobs = Shell.run("/bin/launchctl", ["list"])
            DispatchQueue.main.async { self?.apply(ps: ps, launchctl: jobs, at: now) }
        }
    }

    private func apply(ps: String?, launchctl: String?, at now: Date) {
        inFlight = false
        guard enabled else { return }
        guard let ps else { lastError = "Couldn't list processes"; return }
        if lastError == "Couldn't list processes" { lastError = nil }
        souls.record(snapshot: ps, at: now)
        // Without launchctl's list, nothing can be ruled out as a launchd job: skip this round.
        guard let launchctl else { return }
        current = souls.qualifying(now: now, allowlist: LostSouls.defaultAllowlist,
                                   launchdPIDs: LostSouls.launchdPIDs(fromLaunchctlList: launchctl),
                                   isApp: Self.isRealApp)
        for s in current where s.isNew {
            log.notice("lost soul: \(s.name, privacy: .public) [\(s.pid)] \(Int(s.meanCPU))% for \(s.minutes) min")
            notifier.post(title: "Lost soul",
                          body: "\(s.name) (pid \(s.pid)) has been burning \(Int(s.meanCPU.rounded()))% CPU for \(s.minutes) min with no parent")
        }
        if autoBanish {
            for s in current where now.timeIntervalSince(s.qualifiedSince) >= autoBanishAfter {
                if end(s) {
                    notifier.post(title: "Lost soul banished", body: "Ended \(s.name) (pid \(s.pid)) after 30 min at \(Int(s.meanCPU.rounded()))% CPU")
                }
            }
        }
    }

    /// A regular or accessory app is never a lost soul; a headless binary run
    /// from inside a bundle (Godot --headless) has no NSRunningApplication.
    private static func isRealApp(pid: Int, comm: String) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid_t(pid)) else { return false }
        return app.activationPolicy == .regular || app.activationPolicy == .accessory
    }

    private static func stillSame(_ s: LostSouls.Soul) -> Bool {
        guard let path = executablePath(of: pid_t(s.pid)) else { return false }
        return displayName(path) == displayName(s.comm)
    }

    /// SIGTERM, then SIGKILL after 5 s if the same process is still alive.
    /// Returns true when the signal was delivered.
    @discardableResult
    private func end(_ s: LostSouls.Soul) -> Bool {
        current.removeAll { $0.pid == s.pid }
        guard Self.stillSame(s) else { return false }   // gone or reused: nothing to do
        let pid = pid_t(s.pid)
        guard kill(pid, SIGTERM) == 0 else {
            if errno == EPERM { lastError = "Not allowed to end \(s.name) [\(s.pid)]" }
            return false   // ESRCH: already gone — not an error
        }
        log.notice("ended lost soul \(s.name, privacy: .public) [\(s.pid)]")
        onSweep?(.hatTip)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard Self.stillSame(s), kill(pid, 0) == 0 else { return }
            if kill(pid, SIGKILL) == 0 { log.notice("SIGKILLed lost soul [\(s.pid)]") }
            else if errno == EPERM { self.lastError = "Not allowed to end \(s.name) [\(s.pid)]" }
        }
        return true
    }

    func addMenuItems(to menu: NSMenu) {
        heading("Lost Souls", error: lastError).forEach(menu.addItem)
        let toggle = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self; toggle.state = enabled ? .on : .off
        menu.addItem(indented(toggle))
        if enabled && current.isEmpty {
            let none = NSMenuItem(title: "None wandering", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(indented(none))
        }
        for s in current {
            let row = NSMenuItem(title: "\(s.name) [\(s.pid)]  —  \(Int(s.meanCPU.rounded()))% for \(s.minutes) min",
                                 action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let end = NSMenuItem(title: "End", action: #selector(endSoul(_:)), keyEquivalent: "")
            end.target = self; end.representedObject = s.pid
            let spare = NSMenuItem(title: "Spare", action: #selector(spareSoul(_:)), keyEquivalent: "")
            spare.target = self; spare.representedObject = s.pid
            sub.addItem(end); sub.addItem(spare)
            row.submenu = sub
            menu.addItem(indented(row))
        }
        let auto = NSMenuItem(title: "Banish Automatically", action: #selector(toggleAuto), keyEquivalent: "")
        auto.target = self; auto.state = autoBanish ? .on : .off
        menu.addItem(indented(auto))
    }

    @objc private func toggleEnabled() { enabled.toggle() }
    @objc private func toggleAuto() { autoBanish.toggle() }
    @objc private func endSoul(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int, let s = current.first(where: { $0.pid == pid }) else { return }
        end(s)
    }
    @objc private func spareSoul(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int else { return }
        souls.spare(pid: pid)
        current.removeAll { $0.pid == pid }
    }
}
