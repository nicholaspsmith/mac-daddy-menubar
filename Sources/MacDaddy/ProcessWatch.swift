// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import StatusItemKit

func readProcessLimit() -> Int {
    var size = 0
    sysctlbyname("kern.maxprocperuid", nil, &size, nil, 0)
    var value: Int32 = 0
    return sysctlbyname("kern.maxprocperuid", &value, &size, nil, 0) == 0 && value > 0 ? Int(value) : 2666
}

/// `ps` parsed into ProcRecs; also used by ProcessDetailWindow's own refresh.
func readAllProcs() -> [ProcRec]? {
    guard let text = Shell.run("/bin/ps", ["-axo", "pid,ppid,user,etime,comm", "-ww"]) else { return nil }
    return parseProcs(text)
}

/// Per-user process count against kern.maxprocperuid, crash-loops, top
/// spawners and zombies. Always on. Was Process Monitor.
final class ProcessWatch: NSObject, Duty {
    var onSweep: ((Flourish) -> Void)?
    var onChange: (() -> Void)?

    let limit = readProcessLimit()
    private let warnPct = 85
    private let pollSeconds: TimeInterval = 5
    private let respawnWindow = 12
    private let notifier: Notifier
    private let history = CountHistory(maxLen: 25)
    private let respawn = RespawnDetector(windowSize: 12, minDistinct: 5, minChurnRatio: 5)
    private let pollQueue = DispatchQueue(label: "macdaddy.processwatch")
    private var pollInFlight = false
    private var lastPoll = Date.distantPast
    private var lastNotifiedAtOrAbove = false
    private var latestProcs: [ProcRec] = []
    private(set) var count: Int?
    private var zombies = ZombieReport(count: 0, quittable: nil)
    private var detailWindows: [ProcessDetailWindowController] = []

    init(notifier: Notifier) { self.notifier = notifier }

    var fraction: Double? { processFraction(count: count, limit: limit) }

    func tick(now: Date) {
        guard now.timeIntervalSince(lastPoll) >= pollSeconds - 0.5, !pollInFlight else { return }
        lastPoll = now
        pollInFlight = true
        pollQueue.async { [weak self] in
            let procs = readAllProcs()
            let zps = Shell.run("/bin/ps", ["-axo", "pid=,ppid=,user=,stat=,comm="])
            DispatchQueue.main.async { self?.apply(procs: procs, zombiePS: zps) }
        }
    }

    private func apply(procs: [ProcRec]?, zombiePS: String?) {
        pollInFlight = false
        let user = NSUserName()
        if let all = procs {
            latestProcs = all
            let n = all.reduce(0) { $0 + ($1.user == user ? 1 : 0) }
            count = n
            history.record(n)
            respawn.record(all)
            let pct = n * 100 / max(limit, 1)
            if pct >= warnPct {
                if !lastNotifiedAtOrAbove {
                    notifier.post(title: "Process count high",
                                  body: "\(n) of \(limit) processes (\(pct)%). Kill some before fork() starts failing.")
                    lastNotifiedAtOrAbove = true
                }
            } else if pct < warnPct - 5 {
                lastNotifiedAtOrAbove = false
            }
        } else {
            count = nil
        }
        if let zps = zombiePS { zombies = ZombieCount.parse(zps, user: user) }
        onChange?()
    }

    func addMenuItems(to menu: NSMenu) {
        let title = count.map { "Processes  \($0) / \(limit) (\($0 * 100 / max(limit, 1))%)" } ?? "Processes  —"
        heading(title, error: nil).forEach(menu.addItem)

        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        var spark = history.sparkline()
        if let r = history.range, r.max > r.min { spark += "   \(r.min)→\(r.max)" }
        let sparkItem = NSMenuItem()
        sparkItem.view = MenuBuilder.textView(spark, font: mono, leftPad: 34)
        menu.addItem(sparkItem)

        let loops = respawn.looping()
        if !loops.isEmpty {
            let h = NSMenuItem(title: "⚠ Crash-looping (\(loops.count))", action: nil, keyEquivalent: "")
            h.attributedTitle = NSAttributedString(string: h.title, attributes: [.foregroundColor: NSColor.systemRed])
            let sub = NSMenu()
            for l in loops.prefix(10) {
                sub.addItem(NSMenuItem(title: "\(displayName(l.comm))  —  \(l.distinct) PIDs / peak \(l.peak) live  (in \(respawnWindow * Int(pollSeconds))s)", action: nil, keyEquivalent: ""))
            }
            h.submenu = sub
            menu.addItem(indented(h))
        }

        let spawn = NSMenuItem(title: "Top Spawners", action: nil, keyEquivalent: "")
        let sm = NSMenu()
        let spawners = topSpawners(latestProcs, topN: 10)
        if spawners.isEmpty { sm.addItem(NSMenuItem(title: "(none)", action: nil, keyEquivalent: "")) }
        for s in spawners {
            let i = NSMenuItem(title: "\(s.comm) [\(s.pid)]  —  \(s.descendants) desc", action: #selector(showDetail(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = NSNumber(value: s.pid)
            sm.addItem(i)
        }
        spawn.submenu = sm
        menu.addItem(indented(spawn))

        let z = NSMenuItem(title: "Zombies  \(zombies.count)", action: nil, keyEquivalent: "")
        menu.addItem(indented(z))
        if let p = zombies.quittable {
            let q = NSMenuItem(title: "Quit \(displayName(p.comm)) [\(p.pid)] to reap \(p.zombies)", action: #selector(quitZombieParent(_:)), keyEquivalent: "")
            q.target = self; q.representedObject = NSNumber(value: p.pid)
            q.indentationLevel = 2
            menu.addItem(q)
        }

        let am = NSMenuItem(title: "Open Activity Monitor", action: #selector(openActivityMonitor), keyEquivalent: "")
        am.target = self
        menu.addItem(indented(am))
    }

    @objc private func showDetail(_ sender: NSMenuItem) {
        guard let pid = (sender.representedObject as? NSNumber)?.intValue else { return }
        let c = ProcessDetailWindowController(pid: pid) { [weak self] closed in self?.detailWindows.removeAll { $0 === closed } }
        detailWindows.append(c)
        c.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// SIGTERM to the parent; launchd then reaps its zombies. Only offered for
    /// your own processes, never PID 1 (ZombieCount enforces both).
    @objc private func quitZombieParent(_ sender: NSMenuItem) {
        guard let pid = (sender.representedObject as? NSNumber)?.int32Value else { return }
        kill(pid, SIGTERM)
        lastPoll = .distantPast
        tick(now: Date())
    }

    @objc private func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }
}
