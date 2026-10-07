// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// Hoes: your third-party processes working the CPU — `hoeCPU` % or more for
/// `hoeAfter` seconds. Feed it a `ps -U <uid> -o pid=,ppid=,%cpu=,command= -ww`
/// snapshot every `sampleInterval` seconds with what the app knows about the
/// interesting PIDs; each round says which are hoes, which rules are due, and
/// which hoes vanished while still hot — probably force-quit, which is how
/// Mac Daddy learns. It never kills anything itself.
///
/// Vanishing hot is enough for an app. A command-line program also needs
/// evidence: one that simply finished (an encode, a build) vanishes hot too.
/// Without any, it is held for `window` and counts only if launchd respawns it.
public final class Hoes {
    /// What the app learns about a PID beyond `ps`.
    public struct Detail: Equatable {
        public let path: String
        public let start: Date
        /// The innermost app bundle's ID, when the executable is in one.
        public let bundleID: String?
        /// Not an Apple-signed platform binary.
        public let thirdParty: Bool
        /// The launchd job it runs as, if any.
        public let launchdLabel: String?
        public init(path: String, start: Date, bundleID: String?, thirdParty: Bool, launchdLabel: String?) {
            self.path = path; self.start = start; self.bundleID = bundleID
            self.thirdParty = thirdParty; self.launchdLabel = launchdLabel
        }
    }

    public struct Hoe: Equatable {
        public let pid: Int
        public let start: Date
        public let key: String
        public let name: String
        public let meanCPU: Double
        public let minutes: Int
        /// True the first round it qualifies.
        public let isNew: Bool
    }

    /// Why a vanished hoe looks force-quit, beyond having vanished while hot.
    public enum Evidence: String, Codable, Equatable {
        /// Ended from Mac Daddy's menu: certain.
        case endedHere
        /// Activity Monitor or the Force Quit window was in front within the last minute.
        case forceQuitWindow
        /// It came back under a new PID within a minute (launchd respawned it).
        case respawned
    }

    public struct ForceQuit: Equatable {
        public let pid: Int
        public let key: String
        public let name: String
        public let command: String
        public let ppid: Int
        public let isApp: Bool
        /// Mean %CPU over the hot streak it ended in, and how long that streak ran.
        public let meanCPU: Double
        public let hotSeconds: TimeInterval
        public let evidence: [Evidence]
        public let launchdLabel: String?
        public init(pid: Int, key: String, name: String, command: String, ppid: Int, isApp: Bool,
                    meanCPU: Double, hotSeconds: TimeInterval, evidence: [Evidence], launchdLabel: String?) {
            self.pid = pid; self.key = key; self.name = name; self.command = command; self.ppid = ppid
            self.isApp = isApp; self.meanCPU = meanCPU; self.hotSeconds = hotSeconds
            self.evidence = evidence; self.launchdLabel = launchdLabel
        }
    }

    public struct Respawn: Equatable {
        public let key: String
        public let launchdLabel: String?
        public init(key: String, launchdLabel: String?) { self.key = key; self.launchdLabel = launchdLabel }
    }

    /// A process a rule says to end now.
    public struct Due: Equatable {
        public let pid: Int
        public let start: Date
        public let ruleID: String
        public let name: String
        public let command: String
        /// The latest `%cpu`, as `ps` printed it.
        public let cpu: String
        public let meanCPU: Double
        public let seconds: TimeInterval
        public let samples: Int
        public init(pid: Int, start: Date, ruleID: String, name: String, command: String, cpu: String,
                    meanCPU: Double, seconds: TimeInterval, samples: Int) {
            self.pid = pid; self.start = start; self.ruleID = ruleID; self.name = name; self.command = command
            self.cpu = cpu; self.meanCPU = meanCPU; self.seconds = seconds; self.samples = samples
        }
    }

    public struct Round: Equatable {
        public var hoes: [Hoe] = []
        public var due: [Due] = []
        /// WARN log messages, unstamped.
        public var warnings: [String] = []
        public var forceQuits: [ForceQuit] = []
        public var respawns: [Respawn] = []
        public init() {}
    }

    /// Which PIDs the app should describe in the next round's `details`.
    public struct Interest {
        let floor: Double
        let pids: Set<Int>
        let paths: [String]
        public func wants(pid: Int, cpu: Double, command: String) -> Bool {
            cpu >= floor || pids.contains(pid) || paths.contains { command.hasPrefix($0) }
        }
    }

    public let hoeCPU: Double
    public let hoeAfter: TimeInterval
    /// Below this nothing is tracked: the lowest bar a rule can have.
    public let floor: Double
    public let sampleInterval: TimeInterval
    public let window: TimeInterval = 60

    private struct Sample { let at: Date; let cpu: Double; let text: String }
    private enum Ender { case here, rule }
    private struct Track {
        let start: Date
        let key: String
        let name: String
        let path: String
        var command: String
        var ppid: Int
        let thirdParty: Bool
        var label: String?
        var samples: [Sample] = []
        var isHoe = false
        var everHoe = false
        var warned = Set<String>()
        var ended: Ender?
    }
    private var tracks: [Int: Track] = [:]
    /// `held`: a command-line force-quit still waiting for evidence.
    private var exits: [String: (at: Date, path: String, pid: Int, held: ForceQuit?)] = [:]
    private var lastRound: Date?

    public init(hoeCPU: Double = 80, hoeAfter: TimeInterval = 120, floor: Double = 70, sampleInterval: TimeInterval = 30) {
        self.hoeCPU = hoeCPU; self.hoeAfter = hoeAfter; self.floor = floor; self.sampleInterval = sampleInterval
    }

    public var interest: Interest {
        Interest(floor: floor, pids: Set(tracks.keys), paths: exits.values.map(\.path))
    }

    /// Mac Daddy is ending this exact process: by a rule (never learned from)
    /// or from the menu (certain).
    public func markEnded(pid: Int, start: Date, byRule: Bool) {
        guard let t = tracks[pid], abs(t.start.timeIntervalSince(start)) < 1 else { return }
        tracks[pid]?.ended = byRule ? .rule : .here
    }

    /// Bundle ID for an app, else the executable path.
    public static func key(_ d: Detail) -> String { d.bundleID ?? d.path }

    /// A UA process's label, the innermost app's name, or the executable's.
    public static func name(path: String, bundleID: String?, command: String) -> String {
        if UAWatchdog.isUA(command) { return UAWatchdog.label(command) }
        if let r = path.range(of: ".app/", options: .backwards) {
            return String(path[..<r.lowerBound].split(separator: "/").last ?? "")
        }
        return (path as NSString).lastPathComponent
    }

    public static func killMessage(_ d: Due, rule: HoeRule) -> String {
        "KILLED runaway \(d.name) pid=\(d.pid) cpu=\(d.cpu)% (\(rule.summary), rule \"\(rule.name)\")"
    }

    /// The trailing samples at `threshold` or more, comparing whole percents.
    private static func streak(_ s: [Sample], atLeast threshold: Double) -> ArraySlice<Sample> {
        let i = s.lastIndex { $0.cpu.rounded(.down) < threshold }.map { $0 + 1 } ?? s.startIndex
        return s[i...]
    }
    private static func span(_ s: ArraySlice<Sample>) -> TimeInterval {
        guard let f = s.first, let l = s.last else { return 0 }
        return l.at.timeIntervalSince(f.at)
    }
    private static func mean(_ s: ArraySlice<Sample>) -> Double {
        s.isEmpty ? 0 : s.reduce(0) { $0 + $1.cpu } / Double(s.count)
    }

    private struct Row { let pid: Int; let ppid: Int; let cpu: Double; let text: String; let command: String }
    private static func parse(_ text: String) -> [Row] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(maxSplits: 3, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard f.count == 4, let pid = Int(f[0]), let ppid = Int(f[1]), let cpu = Double(f[2]) else { return nil }
            return Row(pid: pid, ppid: ppid, cpu: cpu, text: String(f[2]), command: String(f[3]))
        }
    }

    /// One round at `now` (when `ps` returned). `rules` are the applicable ones,
    /// in order; the first unpaused match decides. `hidden` keys are never hoes.
    /// After a gap of more than 3 sample intervals (sleep) streaks start over
    /// and no exit is read as a force-quit.
    public func record(ps text: String, at now: Date, details: [Int: Detail], rules: [HoeRule], hidden: Set<String>,
                       frontmostPID: Int?, frontmostBundle: String?, forceQuitWindowAt: Date?, selfPID: Int) -> Round {
        var out = Round()
        let slept = lastRound.map { now.timeIntervalSince($0) > 3 * sampleInterval } ?? false
        lastRound = now
        exits = exits.filter { now.timeIntervalSince($0.value.at) <= window }
        var seen = Set<Int>()

        func exited(_ pid: Int, _ t: Track) {
            guard !slept, t.ended != .rule, t.isHoe, t.thirdParty,
                  let last = t.samples.last, last.cpu.rounded(.down) >= hoeCPU else { return }
            let hot = Self.streak(t.samples, atLeast: hoeCPU)
            var evidence: [Evidence] = []
            if t.ended == .here { evidence.append(.endedHere) }
            if let w = forceQuitWindowAt, w >= last.at.addingTimeInterval(-window), w <= now { evidence.append(.forceQuitWindow) }
            let fq = ForceQuit(pid: pid, key: t.key, name: t.name, command: t.command, ppid: t.ppid,
                               isApp: t.path.contains(".app/Contents/MacOS/"), meanCPU: Self.mean(hot),
                               hotSeconds: Self.span(hot), evidence: evidence, launchdLabel: t.label)
            let held = !fq.isApp && evidence.isEmpty
            if !held { out.forceQuits.append(fq) }
            exits[t.key] = (now, t.path, pid, held ? fq : nil)
        }

        for row in Self.parse(text) where row.pid != selfPID {
            let d = details[row.pid]
            if let d, let e = exits[Self.key(d)], e.pid != row.pid {
                if let fq = e.held {
                    out.forceQuits.append(ForceQuit(pid: fq.pid, key: fq.key, name: fq.name, command: fq.command, ppid: fq.ppid,
                                                    isApp: fq.isApp, meanCPU: fq.meanCPU, hotSeconds: fq.hotSeconds,
                                                    evidence: [.respawned], launchdLabel: fq.launchdLabel))
                }
                out.respawns.append(Respawn(key: Self.key(d), launchdLabel: d.launchdLabel))
                exits[Self.key(d)] = nil
            }
            // A PID now held by another process: the old one exited.
            if let t = tracks[row.pid], let d, abs(t.start.timeIntervalSince(d.start)) > 1 {
                exited(row.pid, t)
                tracks[row.pid] = nil
            }
            // Cooled off: from here an exit is not a force-quit.
            guard row.cpu >= floor else { tracks[row.pid] = nil; continue }
            if tracks[row.pid] == nil {
                guard let d else { continue }
                tracks[row.pid] = Track(start: d.start, key: Self.key(d),
                                        name: Self.name(path: d.path, bundleID: d.bundleID, command: row.command),
                                        path: d.path, command: row.command, ppid: row.ppid,
                                        thirdParty: d.thirdParty, label: d.launchdLabel)
            } else if slept {
                tracks[row.pid]!.samples = []; tracks[row.pid]!.isHoe = false; tracks[row.pid]!.warned = []
            }
            seen.insert(row.pid)
            tracks[row.pid]!.command = row.command
            tracks[row.pid]!.ppid = row.ppid
            if let l = d?.launchdLabel { tracks[row.pid]!.label = l }
            var s = tracks[row.pid]!.samples
            s.append(Sample(at: now, cpu: row.cpu, text: row.text))
            while let f = s.first, now.timeIntervalSince(f.at) > 3600 { s.removeFirst() }
            tracks[row.pid]!.samples = s
        }
        for (pid, t) in tracks where !seen.contains(pid) {
            exited(pid, t)
            tracks[pid] = nil
        }

        for pid in tracks.keys.sorted() {
            guard var t = tracks[pid], t.ended == nil, let last = t.samples.last else { continue }
            let hot = Self.streak(t.samples, atLeast: hoeCPU)
            t.isHoe = t.thirdParty && !hidden.contains(t.key) && !hot.isEmpty && Self.span(hot) >= hoeAfter
            if t.isHoe {
                out.hoes.append(Hoe(pid: pid, start: t.start, key: t.key, name: t.name, meanCPU: Self.mean(hot),
                                    minutes: Int(Self.span(hot) / 60), isNew: !t.everHoe))
                if !t.everHoe {
                    out.warnings.append("WARN \(t.name) pid=\(pid) cpu=\(last.text)% (hoe: ≥\(Int(hoeCPU))% for \(Int(hoeAfter / 60)) min)")
                }
                t.everHoe = true
            }
            if let rule = rules.first(where: { !$0.paused && $0.matches(command: t.command, ppid: t.ppid, key: t.key) }) {
                let run = Self.streak(t.samples, atLeast: Double(rule.threshold))
                let inFront = pid == frontmostPID || frontmostBundle.map { t.path.hasPrefix($0) } == true
                if run.isEmpty {
                    t.warned.remove(rule.id)
                } else if !(rule.skipWhenFrontmost && inFront) {
                    let span = Self.span(run)
                    if span >= Double(rule.minutes * 60) {
                        out.due.append(Due(pid: pid, start: t.start, ruleID: rule.id, name: t.name, command: t.command,
                                           cpu: last.text, meanCPU: Self.mean(run), seconds: span, samples: run.count))
                    } else if t.warned.insert(rule.id).inserted {
                        out.warnings.append("WARN \(t.name) pid=\(pid) cpu=\(last.text)% (\(rule.summary): \(Int(span / 60)) min so far)")
                    }
                }
            }
            tracks[pid] = t
        }
        return out
    }
}
