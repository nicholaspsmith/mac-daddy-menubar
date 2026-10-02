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

/// Processes whose real UID is yours, counted with sysctl(KERN_PROC_RUID) so
/// it works even when the process table is full and spawning `ps` would fail
/// (exactly when the count matters most). Real UID is what both
/// kern.maxprocperuid and `ps -u $USER` count (setuid `login` shells included).
/// nil only if the sysctl itself fails.
func countUserProcesses() -> Int? {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_RUID, Int32(bitPattern: getuid())]
    let stride = MemoryLayout<kinfo_proc>.stride
    for _ in 0..<3 {
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        size += 32 * stride   // room for processes born between the two calls
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: size / stride)
        let rc = buffer.withUnsafeMutableBytes { raw -> Int32 in
            var got = raw.count
            let r = sysctl(&mib, UInt32(mib.count), raw.baseAddress, &got, nil, 0)
            size = got
            return r
        }
        if rc == 0 { return size / stride }
        guard errno == ENOMEM else { return nil }
    }
    return nil
}

/// The executable path of `pid`, or nil when it is gone or unreadable.
func executablePath(of pid: pid_t) -> String? {
    var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let n = proc_pidpath(pid, &buf, UInt32(buf.count))
    guard n > 0 else { return nil }
    return String(cString: buf)
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
    private(set) var fraction: Double?
    private var lastGoodFraction: Double?
    private var zombieError: String?
    private var zombieErrorPID: Int?
    private var zombies = ZombieReport(count: 0, quittable: nil)
    private var detailWindows: [ProcessDetailWindowController] = []

    init(notifier: Notifier) { self.notifier = notifier }

    func tick(now: Date) {
        guard now.timeIntervalSince(lastPoll) >= pollSeconds - 0.5, !pollInFlight else { return }
        lastPoll = now
        pollInFlight = true
        pollQueue.async { [weak self] in
            let n = countUserProcesses()
            let procs = readAllProcs()
            let zps = Shell.run("/bin/ps", ["-axo", "pid=,ppid=,user=,stat=,comm=", "-ww"])
            DispatchQueue.main.async { self?.apply(count: n, procs: procs, zombiePS: zps) }
        }
    }

    /// `n` (sysctl) drives the count, fraction and sparkline; `procs` (ps)
    /// only feeds the menu details and may be nil when the table is full.
    private func apply(count n: Int?, procs: [ProcRec]?, zombiePS: String?) {
        pollInFlight = false
        let user = NSUserName()
        if let all = procs {
            latestProcs = all
            respawn.record(all)
        }
        count = n
        fraction = reportedFraction(reading: processFraction(count: n, limit: limit), lastGood: lastGoodFraction)
        if let n {
            lastGoodFraction = processFraction(count: n, limit: limit)
            history.record(n)
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
        }
        if let zps = zombiePS {
            zombies = ZombieCount.parse(zps, user: user, excludingPID: Int(getpid()))
            // A refused quit stays reported until a poll no longer offers that parent.
            if zombies.quittable?.pid != zombieErrorPID { zombieError = nil; zombieErrorPID = nil }
        }
        onChange?()
    }

    var title: String { count.map { "Processes  \($0) / \(limit) (\($0 * 100 / max(limit, 1))%)" } ?? "Processes  —" }
    var warning: String? { zombieError }

    /// Unlike the other duties, Processes sits at the top level: it is the status.
    func addMenuItems(to menu: NSMenu) {
        heading(title, error: zombieError).forEach(menu.addItem)

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

        if zombies.count > 0 {
            let z = NSMenuItem(title: "Zombies  \(zombies.count)", action: nil, keyEquivalent: "")
            menu.addItem(indented(z))
        }
        if let p = zombies.quittable {
            let q = NSMenuItem(title: "Quit \(displayName(p.comm)) [\(p.pid)] to reap \(p.zombies)", action: #selector(quitZombieParent(_:)), keyEquivalent: "")
            q.target = self; q.representedObject = p
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

    /// SIGTERM to the parent after a confirmation; launchd then reaps its
    /// zombies. ZombieCount only offers your own, non-system processes and
    /// never Mac Daddy; the PID is re-checked here (and again after the alert)
    /// because it may have exited and been reused since the menu was built.
    @objc private func quitZombieParent(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? ZombieParent else { return }
        let pid = pid_t(p.pid)
        guard ZombieCount.stillSameProcess(expectedComm: p.comm, currentPath: executablePath(of: pid)) else { return refresh() }
        let name = displayName(p.comm)
        let alert = NSAlert()
        alert.messageText = "Quit \(name)?"
        alert.informativeText = "Its \(p.zombies) zombie process\(p.zombies == 1 ? "" : "es") will be cleaned up."
        alert.addButton(withTitle: "Quit \(name)")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              ZombieCount.stillSameProcess(expectedComm: p.comm, currentPath: executablePath(of: pid)) else { return refresh() }
        if kill(pid, SIGTERM) == 0 || errno == ESRCH {   // ESRCH: already gone — not an error.
            zombieError = nil; zombieErrorPID = nil
        } else if errno == EPERM {
            zombieError = "Not allowed to quit \(name) [\(pid)]"
            zombieErrorPID = p.pid
        }
        refresh()
    }

    private func refresh() {
        lastPoll = .distantPast
        tick(now: Date())
    }

    @objc private func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }
}
