// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// What Hoes has learned: its rules, the suggestions waiting for a yes or no,
/// and the executables never to suggest (or never to list). Kept as JSON in
/// defaults under `hoes.rules`, `hoes.suggestions` and `hoes.ignored`.
public struct HoesState: Equatable {
    public struct Suggestion: Codable, Equatable {
        public let key: String
        public let name: String
        public var threshold: Int
        public var minutes: Int
        /// What was seen before the force-quit.
        public let meanCPU: Int
        public let observedMinutes: Int
        public let isApp: Bool
        public var restartLabel: String?
        public var evidence: [Hoes.Evidence]
        public let at: Date

        public var prompt: String { "Auto-kill \(name)? (≥\(threshold)% for \(minutes) min)" }
        public var notification: String {
            "You ended \(name) after \(observedMinutes) min at \(meanCPU)% CPU. Auto-kill it next time?"
        }
    }

    public struct Ignored: Codable, Equatable {
        public let key: String
        public let name: String
        /// Ignore (never listed nor suggested) rather than No (never suggested).
        public let hidden: Bool
        public init(key: String, name: String, hidden: Bool) { self.key = key; self.name = name; self.hidden = hidden }
    }

    public enum Outcome: Equatable {
        case suggested(Suggestion)
        case tightened(HoeRule)
        /// A rule already covers it at least as tightly.
        case unchanged(HoeRule)
        /// Ignored, declined, or covered by a built-in.
        case skipped
    }

    public var rules: [HoeRule] = []
    public var suggestions: [Suggestion] = []
    public var ignored: [Ignored] = []

    public init() {}

    public var hiddenKeys: Set<String> { Set(ignored.filter(\.hidden).map(\.key)) }

    /// A probable force-quit: tighten the rule that covers it, or suggest one.
    public mutating func learn(_ fq: Hoes.ForceQuit, now: Date) -> Outcome {
        guard !ignored.contains(where: { $0.key == fq.key }) else { return .skipped }
        let g = HoeRule.guess(meanCPU: fq.meanCPU, hotSeconds: fq.hotSeconds)
        if let i = rules.firstIndex(where: { $0.matches(command: fq.command, ppid: fq.ppid, key: fq.key) }) {
            guard !rules[i].builtIn else { return .skipped }
            guard rules[i].tighten(threshold: g.threshold, minutes: g.minutes) else { return .unchanged(rules[i]) }
            rules[i].tightenedAt = now
            return .tightened(rules[i])
        }
        let s = Suggestion(key: fq.key, name: fq.name, threshold: g.threshold, minutes: g.minutes,
                           meanCPU: Int(fq.meanCPU.rounded()), observedMinutes: Int(fq.hotSeconds / 60), isApp: fq.isApp,
                           restartLabel: fq.launchdLabel, evidence: fq.evidence, at: now)
        suggestions.removeAll { $0.key == fq.key }
        suggestions.append(s)
        return .suggested(s)
    }

    /// It came back on its own: more evidence, and a launchd label to restart it by.
    public mutating func noteRespawn(_ r: Hoes.Respawn) {
        if let i = suggestions.firstIndex(where: { $0.key == r.key }) {
            if !suggestions[i].evidence.contains(.respawned) { suggestions[i].evidence.append(.respawned) }
            if suggestions[i].restartLabel == nil { suggestions[i].restartLabel = r.launchdLabel }
        }
        if let i = rules.firstIndex(where: { $0.match == .executable(r.key) }), rules[i].restartLabel == nil {
            rules[i].restartLabel = r.launchdLabel
        }
    }

    @discardableResult
    public mutating func accept(key: String) -> HoeRule? {
        guard let i = suggestions.firstIndex(where: { $0.key == key }) else { return nil }
        let s = suggestions.remove(at: i)
        let r = HoeRule.learned(key: s.key, name: s.name, threshold: s.threshold, minutes: s.minutes,
                                isApp: s.isApp, restartLabel: s.restartLabel)
        rules.removeAll { $0.id == r.id }
        rules.append(r)
        return r
    }

    /// No: never suggest it again (until un-ignored).
    public mutating func decline(key: String) {
        guard let i = suggestions.firstIndex(where: { $0.key == key }) else { return }
        let s = suggestions.remove(at: i)
        if !ignored.contains(where: { $0.key == key }) { ignored.append(Ignored(key: key, name: s.name, hidden: false)) }
    }

    /// Ignore: never list nor suggest it again (until un-ignored).
    public mutating func ignore(key: String, name: String) {
        suggestions.removeAll { $0.key == key }
        ignored.removeAll { $0.key == key }
        ignored.append(Ignored(key: key, name: name, hidden: true))
    }

    public mutating func unignore(key: String) { ignored.removeAll { $0.key == key } }

    /// Built-ins can't be deleted, only paused or adjusted.
    @discardableResult
    public mutating func deleteRule(id: String) -> Bool {
        guard let i = rules.firstIndex(where: { $0.id == id }), !rules[i].builtIn else { return false }
        rules.remove(at: i)
        return true
    }

    /// Adds any built-in not yet stored, ahead of the learned rules, `paused`
    /// as given; ones already stored keep the user's adjustments.
    public mutating func ensureBuiltIns(_ builtIns: [HoeRule], paused: Bool) {
        let missing = builtIns.filter { b in !rules.contains { $0.id == b.id } }.map { b -> HoeRule in
            var r = b; r.paused = paused; return r
        }
        let at = rules.lastIndex(where: \.builtIn).map { $0 + 1 } ?? 0
        rules.insert(contentsOf: missing, at: at)
    }

    public static let rulesKey = "hoes.rules", suggestionsKey = "hoes.suggestions", ignoredKey = "hoes.ignored"

    public static func load(from d: UserDefaults) -> HoesState {
        func decode<T: Decodable>(_ key: String) -> [T] {
            d.data(forKey: key).flatMap { try? JSONDecoder().decode([T].self, from: $0) } ?? []
        }
        var s = HoesState()
        s.rules = decode(rulesKey)
        s.suggestions = decode(suggestionsKey)
        s.ignored = decode(ignoredKey)
        return s
    }

    public func save(to d: UserDefaults) {
        let e = JSONEncoder()
        d.set(try? e.encode(rules), forKey: Self.rulesKey)
        d.set(try? e.encode(suggestions), forKey: Self.suggestionsKey)
        d.set(try? e.encode(ignored), forKey: Self.ignoredKey)
    }
}
