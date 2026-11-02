// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import os
import StatusItemKit

private let log = Logger(subsystem: "com.nicholaspsmith.MacDaddy", category: "orphans")


/// The BSD info of a live process, or nil when it is gone.
func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
}

func startDate(_ info: proc_bsdinfo) -> Date {
    Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
}

private func procDetail(_ pid: Int) -> LostSouls.ProcDetail {
    let p = pid_t(pid)
    // The PID macOS holds responsible for `pid` (the app or daemon that
    // launched it, through XPC too); nil when the private call is unavailable.
    let r = Responsibility.shared?(pid)
    return LostSouls.ProcDetail(path: executablePath(of: p), start: bsdInfo(p).map(startDate),
                                responsiblePID: r,
                                responsiblePath: r.flatMap { $0 != pid ? executablePath(of: pid_t($0)) : nil })
}

/// Hoes with no pimp: your own orphaned processes (launchd adopted them) that
/// have averaged over 50% CPU for ten minutes — a hung headless test run, a
/// script whose terminal closed. Part of Hoes since 1.18.0 (it was Street
/// Walkers / Lost Souls, which replaced the Godot-only reaper). Hoes drives it:
/// `tick` while Hoes is on, its rows in Hoes's list. Never kills on its own
/// unless Auto Pimp Slap Hoes With No Pimp is on.
final class OrphanWatch: NSObject {
    var onSweep: ((Flourish) -> Void)?
    /// Called when `current` or the warning changes outside a menu action.
    var onChange: (() -> Void)?

    private enum EndResult { case ended, gone, changed, denied }

    static let autoEndKey = "hoes.autoEndOrphans"

    private let defaults = UserDefaults.standard
    private let notifier: Notifier
    private let sampleSeconds: TimeInterval = 30
    private let autoEndAfter: TimeInterval = 30 * 60
    private var souls = LostSouls()
    private let queue = DispatchQueue(label: "macdaddy.orphans")
    private var inFlight = false
    private var generation = 0
    private var lastSample = Date.distantPast
    private(set) var lastError: String?
    /// The orphan a ⚠ is about; the line clears once that process is gone.
    private var errorSoul: (pid: Int, start: Date)?
    private var banished = Set<String>()
    private(set) var current: [LostSouls.Soul] = []

    init(notifier: Notifier) {
        self.notifier = notifier
        super.init()
        if Responsibility.shared == nil {
            log.error("\(Responsibility.symbol, privacy: .public) unavailable: skipping the responsible-process exclusion")
        }
    }

    /// Hoes was switched off or on: start from nothing, no stale samples, no stale ⚠.
    func reset() {
        souls = LostSouls(sampleInterval: sampleSeconds)
        generation += 1
        current = []; banished = []
        clearError()
    }

    var autoEnd: Bool {
        get { defaults.object(forKey: Self.autoEndKey) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Self.autoEndKey) }
    }

    func tick(now: Date) {
        guard !inFlight, now.timeIntervalSince(lastSample) >= sampleSeconds - 0.5 else { return }
        lastSample = now
        inFlight = true
        let uid = String(getuid())
        let gen = generation
        queue.async { [weak self] in
            let ps = Shell.run("/bin/ps", ["-U", uid, "-o", "pid=,ppid=,%cpu=,etime=,comm=", "-ww"])
            let at = Date()   // when ps returned, not when the tick fired
            let jobs = Shell.run("/bin/launchctl", ["list"])
            var details: [Int: LostSouls.ProcDetail] = [:]
            for line in (ps ?? "").split(separator: "\n") {
                let f = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                if f.count == 3, f[1] == "1", let pid = Int(f[0]) { details[pid] = procDetail(pid) }
            }
            DispatchQueue.main.async { self?.apply(ps: ps, launchctl: jobs, details: details, at: at, generation: gen) }
        }
    }

    private func apply(ps: String?, launchctl: String?, details: [Int: LostSouls.ProcDetail], at now: Date, generation gen: Int) {
        inFlight = false
        guard gen == generation else { return }
        defer { onChange?() }
        guard let ps else { lastError = "Couldn't list processes"; errorSoul = nil; return }
        if lastError == "Couldn't list processes" { clearError() }
        souls.record(snapshot: ps, at: now, detail: { details[$0] })
        if let e = errorSoul, !souls.contains(pid: e.pid, start: e.start) { clearError() }
        // Without launchctl's list, nothing can be ruled out as a launchd job: skip this round.
        guard let launchctl else { return }
        current = souls.qualifying(now: now, allowlist: LostSouls.defaultAllowlist,
                                   launchdJobs: LostSouls.launchdJobs(fromLaunchctlList: launchctl),
                                   isApp: Self.isRealApp)
        let fresh = current.filter(\.isNew)
        for s in fresh {
            log.notice("hoe with no pimp: \(s.name, privacy: .public) [\(s.pid)] \(Int(s.meanCPU))% for \(s.minutes) min")
        }
        let terms = terms
        if fresh.count == 1, let s = fresh.first {
            notifier.post(title: terms.orphanFound,
                          body: terms.orphanBody(name: s.name, pid: s.pid, cpu: Self.pct(s), minutes: s.minutes))
        } else if fresh.count > 1 {
            notifier.post(title: terms.orphansFound(fresh.count),
                          body: terms.orphansBody(fresh.map { "\($0.name) (\(Self.pct($0))%)" }))
        }
        if autoEnd {
            var ended: [LostSouls.Soul] = []
            for s in current where now.timeIntervalSince(s.qualifiedSince) >= autoEndAfter {
                guard banished.insert(Self.key(s)).inserted else { continue }   // once per process
                if end(s) == .ended { ended.append(s) }
            }
            if ended.count == 1, let s = ended.first {
                notifier.post(title: terms.hoes, body: terms.banished(name: s.name, pid: s.pid, cpu: Self.pct(s)))
            } else if ended.count > 1 {
                notifier.post(title: terms.hoes,
                              body: terms.banishedMany(ended.map { "\($0.name) (pid \($0.pid))" }))
            }
        }
    }

    static func pct(_ s: LostSouls.Soul) -> Int { Int(s.meanCPU.rounded()) }
    static func key(_ s: LostSouls.Soul) -> String { "\(s.pid)@\(s.start.timeIntervalSince1970)" }

    /// A regular or accessory app; a headless binary run from inside a bundle
    /// (Godot --headless) has no NSRunningApplication.
    private static func isRealApp(pid: Int) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid_t(pid)) else { return false }
        return app.activationPolicy == .regular || app.activationPolicy == .accessory
    }

    /// Is `pid` still this exact soul: same start time, still orphaned, still yours?
    /// nil when no process has that PID any more.
    private static func verify(_ s: LostSouls.Soul) -> Bool? {
        guard let info = bsdInfo(pid_t(s.pid)) else { return nil }
        return abs(startDate(info).timeIntervalSince(s.start)) < 1 && info.pbi_ppid == 1 && info.pbi_uid == getuid()
    }

    private func clearError() { lastError = nil; errorSoul = nil }
    private func setError(_ text: String, _ s: LostSouls.Soul) { lastError = text; errorSoul = (s.pid, s.start) }

    /// SIGTERM, then SIGKILL after 5 s if the same process is still alive.
    @discardableResult
    private func end(_ s: LostSouls.Soul) -> EndResult {
        current.removeAll { $0.pid == s.pid }
        switch Self.verify(s) {
        case nil: return .gone
        case false?:
            setError(terms.changed(name: s.name), s)
            return .changed
        case true?: break
        }
        let pid = pid_t(s.pid)
        guard kill(pid, SIGTERM) == 0 else {
            if errno == EPERM { setError(terms.notAllowed(name: s.name, pid: s.pid), s); return .denied }
            return .gone   // ESRCH: already gone — not an error
        }
        clearError()
        log.notice("ended hoe with no pimp \(s.name, privacy: .public) [\(s.pid)]")
        onSweep?(.hatTip)
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard Self.verify(s) == true else { return }   // exited, or the PID is someone else's now
            if kill(pid, SIGKILL) == 0 { log.notice("SIGKILLed hoe with no pimp [\(s.pid)]") }
            else if errno == EPERM, let self, gen == self.generation { self.setError(terms.notAllowed(name: s.name, pid: s.pid), s) }
        }
        return .ended
    }

    /// Ends the orphan with this `key` from the menu.
    func end(key: String) {
        guard let s = current.first(where: { Self.key($0) == key }) else { return }
        end(s)
    }

    /// Leaves this orphan alone until it exits.
    func spare(key: String) {
        guard let s = current.first(where: { Self.key($0) == key }) else { return }
        souls.spare(pid: s.pid, start: s.start)
        current.removeAll { $0.pid == s.pid }
    }
}
