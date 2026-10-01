// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// Which headless Godot runs are hung. A headless test run finishes in well
/// under a minute; one alive past the threshold was orphaned and would burn CPU
/// for days. The interactive editor (`-e`, no `--headless`) is never touched.
public enum ReapRule {
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

    /// `psOutput` from `ps -Axo pid=,etime=,command=`.
    public static func pidsToReap(psOutput: String, thresholdSeconds: Int) -> [Int] {
        psOutput.split(separator: "\n").compactMap { line in
            let f = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard f.count >= 3, let pid = Int(f[0]), let age = elapsedSeconds(String(f[1])) else { return nil }
            let exe = f[2]
            let args = f.count == 4 ? f[3] : ""
            guard exe.hasSuffix("MacOS/Godot"),
                  args.split(separator: " ").contains("--headless"),
                  age >= thresholdSeconds else { return nil }
            return pid
        }
    }
}
