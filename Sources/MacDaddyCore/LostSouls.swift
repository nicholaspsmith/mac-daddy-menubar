// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// Lost souls: your own processes that launchd adopted (PPID 1) and that have
/// averaged more than `cpuThreshold` % CPU over the last `window` seconds — a
/// hung headless test run, a runaway script whose terminal closed. Feed it
/// `ps -U <uid> -o pid=,ppid=,%cpu=,etime=,comm= -ww` snapshots; it never
/// kills anything itself.
public final class LostSouls {
    public struct Soul: Equatable {
        public let pid: Int
        public let comm: String
        /// The executable's real path (proc_pidpath), or `comm` when unknown.
        public let path: String
        public let name: String
        /// When the process started: its identity, with `pid`.
        public let start: Date
        public let meanCPU: Double
        /// Whole minutes of samples behind `meanCPU` (orphaned the whole time).
        public let minutes: Int
        /// When it first qualified this time round.
        public let qualifiedSince: Date
        /// True only the first time this process qualifies (notify once).
        public let isNew: Bool
    }

    /// What the app can learn about a PID beyond `ps`: the real executable
    /// path, the exact start time, and the process macOS holds responsible
    /// for it (`responsibility_get_pid_responsible_for_pid`) with its path.
    public struct ProcDetail: Equatable {
        public let path: String?
        public let start: Date?
        public let responsiblePID: Int?
        public let responsiblePath: String?
        public init(path: String?, start: Date?, responsiblePID: Int?, responsiblePath: String?) {
            self.path = path; self.start = start
            self.responsiblePID = responsiblePID; self.responsiblePath = responsiblePath
        }
    }

    /// Command basenames that are normally orphaned and busy on purpose.
    public static let defaultAllowlist: Set<String> = [
        "launchd", "loginwindow", "WindowServer", "cfprefsd", "distnoted",
        "mdworker", "mdworker_shared", "mds", "mds_stores", "trustd",
        "nsurlsessiond", "UserEventAgent", "secd", "coreaudiod", "ssh-agent",
        "gpg-agent", "tmux", "screen", "mosh-server", "ollama", "MacDaddy",
    ]

    /// XPC services, app extensions and the OS's own binaries are never lost
    /// souls: launchd or their host app runs them as PPID 1 by design.
    public static func isSystemOrHelper(path: String) -> Bool {
        path.contains(".xpc/") || path.contains(".appex/")
            || ["/System/", "/usr/libexec/", "/usr/sbin/", "/Library/Apple/"].contains { path.hasPrefix($0) }
    }

    /// `/Applications/Foo.app/` for any path inside that bundle.
    static func bundleRoot(of path: String) -> String? {
        path.range(of: ".app/").map { String(path[..<$0.upperBound]) }
    }

    private struct Sample { let at: Date; let cpu: Double }
    private struct Track {
        let comm: String
        let start: Date
        let exactStart: Bool
        var detail: ProcDetail?
        var samples: [Sample] = []
        var spared = false
        var everQualified = false
        var qualifiedSince: Date?
        var path: String { detail?.path ?? comm }
    }

    public let window: TimeInterval
    public let cpuThreshold: Double
    public let sampleInterval: TimeInterval
    private var tracks: [Int: Track] = [:]

    public init(window: TimeInterval = 600, cpuThreshold: Double = 50, sampleInterval: TimeInterval = 30) {
        self.window = window
        self.cpuThreshold = cpuThreshold
        self.sampleInterval = sampleInterval
    }

    public var trackedPIDs: [Int] { tracks.keys.sorted() }

    /// Whether this exact process (pid + start time) is still being tracked.
    public func contains(pid: Int, start: Date) -> Bool {
        guard let t = tracks[pid] else { return false }
        return abs(t.start.timeIntervalSince(start)) < 1
    }

    /// Samples needed before a soul can qualify: 80 % of a fully covered window.
    var minSamples: Int { max(2, Int((window / sampleInterval * 0.8).rounded(.up))) }

    /// Adds one snapshot taken at `now` (when `ps` returned). Only orphans
    /// outside the system/helper paths are tracked; a PID that is gone, no
    /// longer orphaned, or now a different process (other start time) is
    /// forgotten, and with it any Spare. A track whose last sample is older
    /// than 3 sample intervals (sleep, or the duty was off) starts over.
    public func record(snapshot: String, at now: Date, detail: (Int) -> ProcDetail? = { _ in nil }) {
        var seen = Set<Int>()
        for line in snapshot.split(separator: "\n") {
            let f = line.split(maxSplits: 4, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard f.count == 5, let pid = Int(f[0]), let ppid = Int(f[1]), let cpu = Double(f[2]),
                  let age = Self.elapsedSeconds(String(f[3])), ppid == 1 else { continue }
            let comm = String(f[4]).trimmingCharacters(in: .whitespaces)
            guard !comm.isEmpty else { continue }
            let d = detail(pid)
            guard !Self.isSystemOrHelper(path: d?.path ?? comm) else { continue }
            let exact = d?.start != nil
            let start = d?.start ?? now.addingTimeInterval(-Double(age))
            seen.insert(pid)
            if let t = tracks[pid], t.comm == comm,
               abs(t.start.timeIntervalSince(start)) <= (exact && t.exactStart ? 1 : 3) {
                if let last = t.samples.last, now.timeIntervalSince(last.at) > 3 * sampleInterval {
                    tracks[pid]!.samples = []
                    tracks[pid]!.qualifiedSince = nil
                }
            } else {
                tracks[pid] = Track(comm: comm, start: start, exactStart: exact)
            }
            if d != nil { tracks[pid]!.detail = d }
            tracks[pid]!.samples.append(Sample(at: now, cpu: cpu))
            // Keep just enough history to span the window.
            var s = tracks[pid]!.samples
            while s.count > 1, s[1].at <= now.addingTimeInterval(-window) { s.removeFirst() }
            tracks[pid]!.samples = s
        }
        tracks = tracks.filter { seen.contains($0.key) }
    }

    /// The souls that qualify now, by PID. `launchdJobs` maps the PIDs in
    /// `launchctl list` to their labels; `isApp(pid)` says whether a PID is a
    /// regular or accessory app. Excluded: allowlisted names, launchd jobs,
    /// apps (an executable in an `.app` bundle that is a running app), and
    /// processes macOS holds a launchd daemon/agent responsible for, or the
    /// app whose bundle they live in. A terminal being responsible does not
    /// count: that is how every orphan started from a shell looks.
    public func qualifying(now: Date, allowlist: Set<String>, launchdJobs: [Int: String],
                           isApp: (Int) -> Bool) -> [Soul] {
        var out: [Soul] = []
        for pid in tracks.keys.sorted() {
            guard var t = tracks[pid] else { continue }
            let path = t.path
            let name = displayName(path)
            var ok = false
            var mean = 0.0
            var span: TimeInterval = 0
            if let first = t.samples.first, let last = t.samples.last, !t.spared {
                span = last.at.timeIntervalSince(first.at)
                mean = t.samples.reduce(0) { $0 + $1.cpu } / Double(t.samples.count)
                ok = span >= window && t.samples.count >= minSamples && mean > cpuThreshold
                    && !allowlist.contains(name)
                    && !Self.isSystemOrHelper(path: path)
                    && launchdJobs[pid] == nil
                    && !(path.contains(".app/Contents/MacOS/") && isApp(pid))
                    && !responsibleExcludes(pid: pid, path: path, detail: t.detail, launchdJobs: launchdJobs, isApp: isApp)
            }
            if ok {
                let isNew = !t.everQualified
                t.everQualified = true
                if t.qualifiedSince == nil { t.qualifiedSince = now }
                out.append(Soul(pid: pid, comm: t.comm, path: path, name: name, start: t.start, meanCPU: mean,
                                minutes: Int(span / 60), qualifiedSince: t.qualifiedSince!, isNew: isNew))
            } else {
                t.qualifiedSince = nil
            }
            tracks[pid] = t
        }
        return out
    }

    private func responsibleExcludes(pid: Int, path: String, detail: ProcDetail?,
                                     launchdJobs: [Int: String], isApp: (Int) -> Bool) -> Bool {
        guard let r = detail?.responsiblePID, r != pid, r > 0 else { return false }
        if let label = launchdJobs[r], !label.hasPrefix("application.") { return true }
        if isApp(r), let rp = detail?.responsiblePath, let root = Self.bundleRoot(of: rp), path.hasPrefix(root) { return true }
        return false
    }

    /// Leaves this process alone until it exits; a new process reusing the PID is not spared.
    public func spare(pid: Int, start: Date) {
        if contains(pid: pid, start: start) { tracks[pid]?.spared = true }
    }

    /// `ps` etime: `[[dd-]hh:]mm:ss`.
    public static func elapsedSeconds(_ etime: String) -> Int? {
        var days = 0
        var clock = Substring(etime)
        if let dash = clock.firstIndex(of: "-") {
            guard let d = Int(clock[..<dash]) else { return nil }
            days = d
            clock = clock[clock.index(after: dash)...]
        }
        let parts = clock.split(separator: ":").map { Int($0) }
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0 != nil }) else { return nil }
        let n = parts.map { $0! }
        let (h, m, s) = n.count == 3 ? (n[0], n[1], n[2]) : (0, n[0], n[1])
        return ((days * 24 + h) * 60 + m) * 60 + s
    }

    /// Running jobs in `launchctl list` output (`PID\tStatus\tLabel`, `-` when not running), PID → label.
    public static func launchdJobs(fromLaunchctlList text: String) -> [Int: String] {
        var jobs: [Int: String] = [:]
        for line in text.split(separator: "\n") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count >= 3, let pid = Int(f[0]) else { continue }
            jobs[pid] = String(f[2])
        }
        return jobs
    }
}
