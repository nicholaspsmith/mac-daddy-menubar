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
            let f = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard f.count == 3, let pid = Int(f[0]), let age = elapsedSeconds(String(f[1])),
                  age >= thresholdSeconds else { return nil }
            // The rest of the line is the command; its path may contain spaces.
            let command = f[2]
            let marker = "MacOS/Godot"
            var search = command.startIndex..<command.endIndex
            while let r = command.range(of: marker, range: search) {
                if r.upperBound == command.endIndex || command[r.upperBound] == " " {
                    let exe = command[..<r.upperBound]
                    let args = command[r.upperBound...]
                    guard !exe.contains(" -"),
                          args.split(separator: " ").contains("--headless") else { return nil }
                    return pid
                }
                search = r.upperBound..<command.endIndex
            }
            return nil
        }
    }
}
