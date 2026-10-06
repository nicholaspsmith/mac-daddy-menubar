// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import StatusItemKit

/// SIGINTs Apple's media-analysis daemons on an interval. Was Media Tracking Killer.
final class TrackerKiller: NSObject, Duty {
    var onSweep: ((Flourish) -> Void)?
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    static let targets: [(process: String, label: String)] = [
        ("mediaanalysisd", "mediaanalysisd (media analysis)"),
        ("mediaanalysisd-access", "mediaanalysisd-access"),
        ("photoanalysisd", "photoanalysisd (photo analysis)"),
    ]
    static let intervalChoices = [5, 15, 30, 60]
    private var lastSweep = Date.distantPast
    private(set) var killsThisSession = 0

    var enabled: Bool {
        get { defaults.object(forKey: "tracker.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "tracker.enabled"); onChange?() }
    }
    var intervalSeconds: Int {
        get { let v = defaults.integer(forKey: "tracker.intervalSeconds"); return Self.intervalChoices.contains(v) ? v : 15 }
        set { defaults.set(newValue, forKey: "tracker.intervalSeconds") }
    }
    func targetEnabled(_ p: String) -> Bool { defaults.object(forKey: "tracker.target.\(p)") as? Bool ?? true }

    func tick(now: Date) {
        if enabled && now.timeIntervalSince(lastSweep) >= Double(intervalSeconds) - 0.5 { sweep(now: now) }
    }

    /// killall exits non-zero when nothing matched, which Shell.run reports as nil.
    private func sweep(now: Date) {
        lastSweep = now
        var hit = false
        for t in Self.targets where targetEnabled(t.process) {
            if Shell.run("/usr/bin/killall", ["-SIGINT", t.process]) != nil { killsThisSession += 1; hit = true }
        }
        if hit { onSweep?(.hatTip) }
    }

    var title: String { terms.trackerTitle(enabled: enabled, kills: killsThisSession) }
    var warning: String? { nil }

    func addMenuItems(to menu: NSMenu) {
        warningItems().forEach(menu.addItem)
        menu.addItem(toggleItem("Enabled", isOn: enabled, in: menu) { [weak self] in self?.enabled = $0 })
        let killNowItem = NSMenuItem(title: terms.killNow(count: killsThisSession), action: #selector(killNow), keyEquivalent: "")
        killNowItem.target = self
        menu.addItem(killNowItem)

        let interval = NSMenuItem(title: "Interval", action: nil, keyEquivalent: "")
        let im = NSMenu()
        for s in Self.intervalChoices {
            let i = NSMenuItem(title: "\(s) seconds", action: #selector(setInterval(_:)), keyEquivalent: "")
            i.target = self; i.tag = s; i.state = s == intervalSeconds ? .on : .off
            im.addItem(i)
        }
        interval.submenu = im
        menu.addItem(interval)

        let procs = NSMenuItem(title: "Processes", action: nil, keyEquivalent: "")
        let pm = NSMenu()
        for t in Self.targets {
            let p = t.process
            pm.addItem(ToggleMenuItem.make(title: t.label, isOn: targetEnabled(p)) { [weak self] on in
                self?.defaults.set(on, forKey: "tracker.target.\(p)")
            })
        }
        procs.submenu = pm
        menu.addItem(procs)
    }

    @objc private func killNow() { sweep(now: Date()) }
    @objc private func setInterval(_ s: NSMenuItem) { intervalSeconds = s.tag }
}
