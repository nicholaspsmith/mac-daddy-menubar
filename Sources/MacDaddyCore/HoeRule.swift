// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// When Hoes ends a process on its own: one that matches, at `threshold` % CPU
/// or more for `minutes` (0 = on sight). Learned rules match one executable;
/// built-ins (the UA watchdog) match by command line.
public struct HoeRule: Codable, Equatable {
    public enum Match: Codable, Equatable {
        /// A learned rule: the app's bundle ID, or the executable's path.
        case executable(String)
        /// A built-in: the command line contains one of `any` and none of `none`.
        case command(any: [String], none: [String], orphanedOnly: Bool)
    }

    /// SIGTERM then SIGKILL after 5 s, or SIGKILL at once.
    public enum Action: String, Codable { case terminate, kill }

    public var id: String
    public var name: String
    public var match: Match
    public var threshold: Int
    public var minutes: Int
    public var action: Action
    /// The launchd job to `kickstart -k` after a kill, when known.
    public var restartLabel: String?
    public var restartAfterKill: Bool
    /// Restart only when the command contains one of these; empty = always.
    public var restartOnlyIf: [String]
    public var skipWhenFrontmost: Bool
    public var paused: Bool
    public var builtIn: Bool
    /// The rule applies only while this path exists (the software it guards is installed).
    public var requiresPath: String?
    /// When a later force-quit last tightened it.
    public var tightenedAt: Date?

    public static let thresholdChoices = [70, 80, 90, 95, 98]
    public static let minuteChoices = [0, 1, 2, 5, 10, 15, 30]

    public init(id: String, name: String, match: Match, threshold: Int, minutes: Int, action: Action = .terminate,
                restartLabel: String? = nil, restartAfterKill: Bool = false, restartOnlyIf: [String] = [],
                skipWhenFrontmost: Bool = false, paused: Bool = false, builtIn: Bool = false,
                requiresPath: String? = nil, tightenedAt: Date? = nil) {
        self.id = id; self.name = name; self.match = match
        self.threshold = threshold; self.minutes = minutes; self.action = action
        self.restartLabel = restartLabel; self.restartAfterKill = restartAfterKill; self.restartOnlyIf = restartOnlyIf
        self.skipWhenFrontmost = skipWhenFrontmost; self.paused = paused; self.builtIn = builtIn
        self.requiresPath = requiresPath; self.tightenedAt = tightenedAt
    }

    /// A rule the user accepted from a suggestion. Apps are spared while in front.
    public static func learned(key: String, name: String, threshold: Int, minutes: Int, isApp: Bool,
                               restartLabel: String?) -> HoeRule {
        HoeRule(id: key, name: name, match: .executable(key), threshold: threshold, minutes: minutes,
                restartLabel: restartLabel, skipWhenFrontmost: isApp)
    }

    /// `key` is the process's bundle ID or executable path (nil when unknown).
    public func matches(command: String, ppid: Int, key: String?) -> Bool {
        switch match {
        case .executable(let k):
            return key == k
        case let .command(any, none, orphanedOnly):
            return any.contains { command.contains($0) } && !none.contains { command.contains($0) }
                && (!orphanedOnly || ppid == 1)
        }
    }

    /// The launchd label to kickstart after ending `command`, or nil.
    public func restart(after command: String) -> String? {
        guard restartAfterKill, let restartLabel else { return nil }
        return restartOnlyIf.isEmpty || restartOnlyIf.contains { command.contains($0) } ? restartLabel : nil
    }

    public var summary: String { minutes == 0 ? "≥\(threshold)% on sight" : "≥\(threshold)% for \(minutes) min" }

    /// Mac Daddy's guess from a force-quit: the sustained mean less 10, to the
    /// nearest 5, within 80…98; half the time it ran hot, in whole minutes, 2…30.
    public static func guess(meanCPU: Double, hotSeconds: TimeInterval) -> (threshold: Int, minutes: Int) {
        let t = Int(((meanCPU - 10) / 5).rounded()) * 5
        let m = Int((hotSeconds / 2 / 60).rounded())
        return (min(max(t, 80), 98), min(max(m, 2), 30))
    }

    /// Lowers the bar and the wait to `threshold`/`minutes` where those are
    /// lower. True when anything changed.
    @discardableResult
    public mutating func tighten(threshold t: Int, minutes m: Int) -> Bool {
        let (nt, nm) = (min(threshold, t), min(minutes, m))
        defer { threshold = nt; minutes = nm }
        return nt != threshold || nm != minutes
    }
}
