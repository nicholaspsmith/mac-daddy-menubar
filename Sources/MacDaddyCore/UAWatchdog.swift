// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// Decides which Universal Audio processes have run away. Feed it one
/// `ps -Ao pid=,ppid=,pcpu=,command= -ww` snapshot per minute; it never kills
/// anything itself. The rules are the old `ua-watchdog.sh` agent's:
///   * an orphaned UA Mixer Helper (PPID 1) at `orphanCPU` % or more is killed
///     at once — the bug that silently takes Apollo audio down;
///   * the real-time UA Mixer Engine needs `cpuEngine` % for `ticksEngine` samples in a row;
///   * every other UA process needs `cpu` % for `ticks` samples in a row.
/// Counts are per PID and drop when a sample falls below the bar. Only the
/// integer part of `%cpu` is compared, as the script did.
public struct UAWatchdog {
    public enum Role: Equatable { case helper, engine, other }

    public struct Proc: Equatable {
        public let pid: Int
        public let ppid: Int
        /// `%cpu` exactly as `ps` printed it; the log quotes it.
        public let cpu: String
        public let command: String
        public init(pid: Int, ppid: Int, cpu: String, command: String) {
            self.pid = pid; self.ppid = ppid; self.cpu = cpu; self.command = command
        }
    }

    public struct Kill: Equatable {
        public let pid: Int
        public let label: String
        public init(pid: Int, label: String) { self.pid = pid; self.label = label }
    }

    /// What one snapshot calls for: SIGKILL these, log these messages (in
    /// order, unstamped), and kickstart the mixer engine if the audio path was hit.
    public struct Scan: Equatable {
        public var kills: [Kill] = []
        public var messages: [String] = []
        public var audioPathHit = false
        public init() {}

        /// The notification body, or nil when nothing was killed.
        public var notification: String? {
            guard let first = kills.first else { return nil }
            return "Killed runaway \(first.label)" + (audioPathHit ? " — audio restored" : "")
        }
    }

    /// Logged after the mixer engine is kickstarted.
    public static let kickstartMessage = "kickstarted UA mixer engine to restore audio path"

    public let cpu: Int
    public let cpuEngine: Int
    public let orphanCPU: Int
    public let ticks: Int
    public let ticksEngine: Int
    /// Consecutive samples over the bar, by PID, for processes not yet killed.
    public private(set) var pending: [Int: Int] = [:]

    public init(cpu: Int = 90, cpuEngine: Int = 98, orphanCPU: Int = 80, ticks: Int = 2, ticksEngine: Int = 3) {
        self.cpu = cpu; self.cpuEngine = cpuEngine; self.orphanCPU = orphanCPU
        self.ticks = ticks; self.ticksEngine = ticksEngine
    }

    /// Forget every pending count (the duty was turned off and on).
    public mutating func reset() { pending = [:] }

    /// The install folders, or the engine/helper name.
    public static func isUA(_ command: String) -> Bool {
        command.contains("/Universal Audio/") || command.contains("UA Connect.app") || command.contains("UA Mixer")
    }

    /// A readable name and whether it is on the audio path.
    public static func classify(_ command: String) -> (label: String, role: Role) {
        if command.contains("UA Mixer Helper.app") { return ("UA Mixer Helper", .helper) }
        if command.contains("UA Mixer Engine.app") { return ("UA Mixer Engine", .engine) }
        if command.contains("UA Connect.app") { return ("UA Connect", .other) }
        if command.contains("UAD Meter") { return ("UAD Meter", .other) }
        if command.contains("UAD Console.app") { return ("UAD Console", .other) }
        // zsh's `:t`: everything after the last slash of the whole command line.
        return (command.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? command, .other)
    }

    public static func parse(ps text: String) -> [Proc] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(maxSplits: 3, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard f.count == 4, let pid = Int(f[0]), let ppid = Int(f[1]) else { return nil }
            return Proc(pid: pid, ppid: ppid, cpu: String(f[2]), command: String(f[3]))
        }
    }

    public mutating func scan(ps text: String) -> Scan {
        var out = Scan()
        var next: [Int: Int] = [:]
        for p in Self.parse(ps: text) where Self.isUA(p.command) {
            let whole = Int(p.cpu.prefix { $0 != "." }) ?? 0
            let (label, role) = Self.classify(p.command)
            if role == .helper && p.ppid == 1 && whole >= orphanCPU {
                out.kills.append(Kill(pid: p.pid, label: label))
                out.messages.append("KILLED orphaned \(label) pid=\(p.pid) cpu=\(p.cpu)% (fast-path: PPID=1)")
                out.audioPathHit = true
                continue
            }
            let (bar, need) = role == .engine ? (cpuEngine, ticksEngine) : (cpu, ticks)
            guard whole >= bar else { continue }
            let count = (pending[p.pid] ?? 0) + 1
            if count >= need {
                out.kills.append(Kill(pid: p.pid, label: label))
                out.messages.append("KILLED runaway \(label) pid=\(p.pid) cpu=\(p.cpu)% (>=\(bar)% x \(count) ticks)")
                if role != .other { out.audioPathHit = true }
            } else {
                next[p.pid] = count
                out.messages.append("WARN \(label) pid=\(p.pid) cpu=\(p.cpu)% (tick \(count)/\(need) >=\(bar)%)")
            }
        }
        pending = next
        return out
    }

    /// Whether `launchctl print-disabled gui/<uid>` lists `label` as disabled
    /// (`=> disabled`, or `=> true` on older macOS).
    public static func isDisabled(_ label: String, printDisabled text: String) -> Bool {
        text.split(separator: "\n").contains { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t == "\"\(label)\" => disabled" || t == "\"\(label)\" => true"
        }
    }
}
