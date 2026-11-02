// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// The folded words of one searchable thing, built once so a keystroke only compares strings.
public struct MatchTarget: Sendable {
    public let words: [String]
    public let initials: String
    public let joined: String

    public init(_ fields: [String]) {
        let ws = fields.flatMap { MatchTarget.split(Query.fold($0)) }
        words = ws
        initials = String(ws.compactMap(\.first))
        joined = ws.joined()
    }

    static func split(_ s: String) -> [String] {
        s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}

public enum Matcher {
    public static let prefixScore = 3.0
    public static let acronymScore = 2.0
    public static let subsequenceScore = 1.0

    /// nil unless every query word matches the target; otherwise the mean of each word's best match.
    /// A word that starts a target word scores 3–4 (4 for the whole word), plus 0.5 when the query's
    /// first word starts the target's first word. Initials score 2, letters in order score 1.
    public static func score(_ query: Query, _ target: MatchTarget) -> Double? {
        guard !query.words.isEmpty, !target.words.isEmpty else { return nil }
        var total = 0.0
        var constraintCount = 0
        for (i, qword) in query.words.enumerated() {
            let q = MatchTarget.split(qword).joined()
            if q.isEmpty { continue }   // a word of pure punctuation constrains nothing
            guard let best = best(q, target, isFirst: i == 0) else { return nil }
            total += best
            constraintCount += 1
        }
        guard constraintCount > 0 else { return nil }
        return total / Double(constraintCount)
    }

    static func best(_ q: String, _ t: MatchTarget, isFirst: Bool) -> Double? {
        var best: Double?
        for (i, w) in t.words.enumerated() where w.hasPrefix(q) {
            var s = prefixScore + Double(q.count) / Double(w.count)
            if isFirst && i == 0 { s += 0.5 }
            best = max(best ?? 0, s)
        }
        if best == nil, q.count >= 2, t.initials.hasPrefix(q) { best = acronymScore }
        if best == nil, isSubsequence(q, of: t.joined) { best = subsequenceScore }
        return best
    }

    static func isSubsequence(_ q: String, of s: String) -> Bool {
        var it = s.makeIterator()
        outer: for c in q {
            while let d = it.next() { if d == c { continue outer } }
            return false
        }
        return true
    }
}
