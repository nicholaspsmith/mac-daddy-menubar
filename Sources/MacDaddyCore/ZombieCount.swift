// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

public struct ZombieParent: Equatable {
    public let pid: Int
    public let comm: String
    public let zombies: Int
    public init(pid: Int, comm: String, zombies: Int) { self.pid = pid; self.comm = comm; self.zombies = zombies }
}

public struct ZombieReport: Equatable {
    public let count: Int
    /// The parent worth quitting: most zombies, yours, never launchd (PID 1).
    /// Quitting it lets launchd reap every zombie it left behind.
    public let quittable: ZombieParent?
    public init(count: Int, quittable: ZombieParent?) { self.count = count; self.quittable = quittable }
}

public enum ZombieCount {
    /// `psOutput` from `ps -axo pid=,ppid=,user=,stat=,comm=`.
    public static func parse(_ psOutput: String, user: String) -> ZombieReport {
        struct Row { let pid: Int; let ppid: Int; let user: String; let stat: String; let comm: String }
        let rows: [Row] = psOutput.split(separator: "\n").compactMap { line in
            let f = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard f.count == 5, let pid = Int(f[0]), let ppid = Int(f[1]) else { return nil }
            return Row(pid: pid, ppid: ppid, user: String(f[2]), stat: String(f[3]), comm: f[4].trimmingCharacters(in: .whitespaces))
        }
        let zombies = rows.filter { $0.stat.hasPrefix("Z") }
        let byParent = Dictionary(grouping: zombies, by: \.ppid).mapValues(\.count)
        let byPID = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let best = byParent
            .compactMap { ppid, n -> ZombieParent? in
                guard ppid > 1, let parent = byPID[ppid], parent.user == user else { return nil }
                return ZombieParent(pid: ppid, comm: parent.comm, zombies: n)
            }
            .max { ($0.zombies, -$0.pid) < ($1.zombies, -$1.pid) }
        return ZombieReport(count: zombies.count, quittable: best)
    }
}
