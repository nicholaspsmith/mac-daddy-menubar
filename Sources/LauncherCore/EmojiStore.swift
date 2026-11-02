// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation

public final class EmojiStore {
    static let aliasBonus = 2.0
    static let recentBonus = 0.5

    public let all: [Emoji]
    public let groups: [String]
    private let targets: [MatchTarget]
    private let indexByChar: [String: Int]

    public init(data: Data) throws {
        all = try JSONDecoder().decode([Emoji].self, from: data)
        targets = all.map { MatchTarget([$0.name] + $0.keywords) }
        indexByChar = Dictionary(all.enumerated().map { ($1.char, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        groups = all.map(\.group).filter { seen.insert($0).inserted }
    }

    public func emoji(for char: String) -> Emoji? { indexByChar[char].map { all[$0] } }

    /// Ranked emoji for `query`, matching name, CLDR keywords and the user's aliases in any
    /// word order. An empty query lists recents first, then every emoji in Unicode order.
    public func search(_ query: Query, aliases: [String: [String]], recents: [String]) -> [EmojiHit] {
        let recentRank = Dictionary(recents.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        if query.isEmpty {
            let recent = recents.compactMap(emoji(for:)).map { EmojiHit(emoji: $0, score: 0) }
            let rest = all.filter { recentRank[$0.char] == nil }.map { EmojiHit(emoji: $0, score: 0) }
            return recent + rest
        }
        var hits: [(hit: EmojiHit, order: Int)] = []
        for (i, e) in all.enumerated() {
            var s = Matcher.score(query, targets[i])
            // The alias bonus is for a real (prefix-level) alias match only; letters scattered
            // through an alias ("nd" in "nerd") match without it, or they'd reach the main list.
            if let names = aliases[e.char], !names.isEmpty, let a = Matcher.score(query, MatchTarget(names)) {
                s = max(s ?? 0, a >= Matcher.prefixScore ? a + Self.aliasBonus : a)
            }
            guard var score = s else { continue }
            if let r = recentRank[e.char] {
                score += Self.recentBonus * (1 - Double(r) / Double(max(recents.count, 1)))
            }
            hits.append((EmojiHit(emoji: e, score: score), i))
        }
        return hits.sorted { $0.hit.score != $1.hit.score ? $0.hit.score > $1.hit.score : $0.order < $1.order }
            .map(\.hit)
    }
}
