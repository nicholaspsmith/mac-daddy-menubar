// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

// MARK: - Respawn-loop detector

// Records per-comm PIDs at each poll, then flags names that look like a
// crash loop rather than a worker pool. Two patterns we need to tell apart:
//
//   crash loop:  peak simultaneous ≈ 1, but many distinct PIDs over time
//                (one slot keeps getting replaced — what contactsd did
//                during the May 19 incident).
//
//   worker pool: peak simultaneous = N, many distinct PIDs over time
//                (mdworker_shared, plugin-container, ExtensionKit
//                helpers — all designed to be short-lived).
//
// The discriminator is `distinct / peak`: how many times each slot was
// replaced inside the window. Flag only when that ratio is high enough
// that normal short-lived helpers don't trip it.
//
// Also excluded: `ps` (we spawn it every poll, so it'd always self-flag)
// and `<defunct>` (a state, not an identity — every reaped zombie ends
// up there regardless of original name).
public final class RespawnDetector {
    /// Per poll: comm → (pid → ppid).
    private var snapshots: [[String: [Int: Int]]] = []
    private let windowSize: Int
    private let minDistinct: Int
    private let minChurnRatio: Int

    private static let excluded: Set<String> = ["ps", "<defunct>"]

    public init(windowSize: Int, minDistinct: Int, minChurnRatio: Int) {
        self.windowSize = windowSize
        self.minDistinct = minDistinct
        self.minChurnRatio = minChurnRatio
    }

    public func record(_ procs: [ProcRec]) {
        var byComm: [String: [Int: Int]] = [:]
        for p in procs {
            byComm[p.comm, default: [:]][p.pid] = p.ppid
        }
        snapshots.append(byComm)
        if snapshots.count > windowSize { snapshots.removeFirst() }
    }

    public struct Looping: Equatable {
        public let comm: String
        public let distinct: Int
        public let peak: Int
        /// The PID that started most of the instances: whatever keeps restarting it.
        public let parent: Int
        /// A PID of it alive at the latest poll, if any.
        public let livePID: Int?

        public init(comm: String, distinct: Int, peak: Int, parent: Int = 1, livePID: Int? = nil) {
            self.comm = comm
            self.distinct = distinct
            self.peak = peak
            self.parent = parent
            self.livePID = livePID
        }
    }

    /// `ignoring`: basenames restarted on purpose, e.g. what Federal Agents
    /// (Media Tracking) is killing on its interval, which launchd brings back.
    public func looping(ignoring: Set<String> = []) -> [Looping] {
        var union: [String: [Int: Int]] = [:]
        var peak: [String: Int] = [:]
        for snap in snapshots {
            for (c, pids) in snap {
                union[c, default: [:]].merge(pids) { a, _ in a }
                peak[c] = max(peak[c] ?? 0, pids.count)
            }
        }
        let latest = snapshots.last ?? [:]
        return union.compactMap { (c, pids) -> Looping? in
            let basename = (c as NSString).lastPathComponent
            if Self.excluded.contains(basename) || ignoring.contains(basename) { return nil }
            let distinct = pids.count
            let p = max(peak[c] ?? 1, 1)
            guard distinct > minDistinct, distinct / p >= minChurnRatio else { return nil }
            let parents = Dictionary(grouping: pids.values, by: { $0 }).mapValues(\.count)
            let parent = parents.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key ?? 1
            return Looping(comm: c, distinct: distinct, peak: p, parent: parent, livePID: latest[c]?.keys.max())
        }
        .sorted { $0.distinct > $1.distinct }
    }
}
