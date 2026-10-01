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
        public let name: String
        public let meanCPU: Double
        /// Whole minutes of samples behind `meanCPU` (orphaned the whole time).
        public let minutes: Int
        /// When it first qualified this time round.
        public let qualifiedSince: Date
        /// True only the first time this process qualifies (notify once).
        public let isNew: Bool
    }

    /// Command basenames that are normally orphaned and busy on purpose.
    public static let defaultAllowlist: Set<String> = [
        "launchd", "loginwindow", "WindowServer", "cfprefsd", "distnoted",
        "mdworker", "mdworker_shared", "mds", "mds_stores", "trustd",
        "nsurlsessiond", "UserEventAgent", "secd", "coreaudiod", "ssh-agent",
        "gpg-agent", "tmux", "screen", "mosh-server", "ollama", "MacDaddy",
    ]

    private struct Sample { let at: Date; let cpu: Double }
    private struct Track {
        let comm: String
        let start: Date
        var samples: [Sample] = []
        var spared = false
        var everQualified = false
        var qualifiedSince: Date?
    }

    public let window: TimeInterval
    public let cpuThreshold: Double
    private var tracks: [Int: Track] = [:]

    public init(window: TimeInterval = 600, cpuThreshold: Double = 50) {
        self.window = window
        self.cpuThreshold = cpuThreshold
    }

    public var trackedPIDs: [Int] { tracks.keys.sorted() }

    /// Adds one snapshot. Only orphans are tracked; a PID that is gone, no
    /// longer orphaned, or now a different process (other comm or start time)
    /// is forgotten, and with it any Spare.
    public func record(snapshot: String, at now: Date) {
        var seen = Set<Int>()
        for line in snapshot.split(separator: "\n") {
            let f = line.split(maxSplits: 4, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard f.count == 5, let pid = Int(f[0]), let ppid = Int(f[1]), let cpu = Double(f[2]),
                  let age = Self.elapsedSeconds(String(f[3])), ppid == 1 else { continue }
            let comm = String(f[4]).trimmingCharacters(in: .whitespaces)
            guard !comm.isEmpty else { continue }
            let start = now.addingTimeInterval(-Double(age))
            seen.insert(pid)
            if let t = tracks[pid], t.comm == comm, abs(t.start.timeIntervalSince(start)) <= 3 {
                // same process
            } else {
                tracks[pid] = Track(comm: comm, start: start)
            }
            tracks[pid]!.samples.append(Sample(at: now, cpu: cpu))
            // Keep just enough history to span the window.
            var s = tracks[pid]!.samples
            while s.count > 1, s[1].at <= now.addingTimeInterval(-window) { s.removeFirst() }
            tracks[pid]!.samples = s
        }
        tracks = tracks.filter { seen.contains($0.key) }
    }

    /// The souls that qualify now, by PID. `isApp(pid, comm)` is asked only for
    /// executables inside an app bundle; return true for a real (regular or
    /// accessory) app, which is never a lost soul.
    public func qualifying(now: Date, allowlist: Set<String>, launchdPIDs: Set<Int>,
                           isApp: (Int, String) -> Bool) -> [Soul] {
        var out: [Soul] = []
        for pid in tracks.keys.sorted() {
            guard var t = tracks[pid] else { continue }
            let name = displayName(t.comm)
            var ok = false
            var mean = 0.0
            var span: TimeInterval = 0
            if let first = t.samples.first, let last = t.samples.last, !t.spared {
                span = last.at.timeIntervalSince(first.at)
                mean = t.samples.reduce(0) { $0 + $1.cpu } / Double(t.samples.count)
                ok = span >= window && mean > cpuThreshold
                    && !allowlist.contains(name)
                    && !launchdPIDs.contains(pid)
                    && !(t.comm.contains(".app/Contents/MacOS/") && isApp(pid, t.comm))
            }
            if ok {
                let isNew = !t.everQualified
                t.everQualified = true
                if t.qualifiedSince == nil { t.qualifiedSince = now }
                out.append(Soul(pid: pid, comm: t.comm, name: name, meanCPU: mean,
                                minutes: Int(span / 60), qualifiedSince: t.qualifiedSince!, isNew: isNew))
            } else {
                t.qualifiedSince = nil
            }
            tracks[pid] = t
        }
        return out
    }

    /// Leaves this process alone until it exits; a new process reusing the PID is not spared.
    public func spare(pid: Int) { tracks[pid]?.spared = true }

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

    /// PIDs of running jobs in `launchctl list` output (`PID\tStatus\tLabel`, `-` when not running).
    public static func launchdPIDs(fromLaunchctlList text: String) -> Set<Int> {
        Set(text.split(separator: "\n").compactMap { line in
            line.split(separator: "\t", omittingEmptySubsequences: false).first.flatMap { Int($0) }
        })
    }
}
