// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation

public final class AppProvider: Provider {
    private let index: AppIndex
    private let usage: UsageStore
    private var targets: [(app: AppEntry, target: MatchTarget)] = []
    private var builtGeneration = -1

    public init(index: AppIndex, usage: UsageStore) {
        self.index = index
        self.usage = usage
    }

    public func results(for query: Query) -> [ResultItem] {
        guard !query.isEmpty else { return [] }
        if builtGeneration != index.generation {
            targets = index.apps.map { ($0, MatchTarget([$0.name])) }
            builtGeneration = index.generation
        }
        return targets.compactMap { app, target in
            guard let s = Matcher.score(query, target) else { return nil }
            return ResultItem(id: "app:\(app.key)", kind: .app, title: app.name,
                              subtitle: Self.abbreviate(app.location.path), icon: .app(app.url),
                              score: s + usage.boost(for: app.key), action: .open(app.url),
                              alternate: .reveal(app.location), usageKey: app.key)
        }
    }

    static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

public struct CalculatorProvider: Provider {
    public init() {}
    public func results(for query: Query) -> [ResultItem] {
        guard let v = Calculator.evaluate(query.raw) else { return [] }
        let text = NumberText.answer(v)
        return [ResultItem(id: "calc", kind: .answer, title: "= \(text)",
                           subtitle: query.raw.trimmingCharacters(in: .whitespaces),
                           icon: .symbol("equal.circle"), score: ResultItem.pinnedScore, action: .copy(text))]
    }
}

public struct ConverterProvider: Provider {
    private let system: () -> UnitSystem
    public init(system: @escaping () -> UnitSystem) { self.system = system }
    public func results(for query: Query) -> [ResultItem] {
        guard let c = Converter(system: system()).convert(query.raw) else { return [] }
        return [ResultItem(id: "convert", kind: .answer, title: "= \(c.withUnit)",
                           subtitle: "\(c.inputText) → \(c.to)", icon: .symbol("arrow.left.arrow.right.circle"),
                           score: ResultItem.pinnedScore, action: .copy(c.bare),
                           alternate: .copy(c.withUnit), alternateLabel: "Copy with unit")]
    }
}

public struct EmojiCommandProvider: Provider {
    static let target = MatchTarget(["Emoji", "Search Emoji"])
    public init() {}
    public func results(for query: Query) -> [ResultItem] {
        guard !query.isEmpty else { return [] }
        let pinned = query.folded == "e" || query.folded == "emoji"
        guard let score = pinned ? ResultItem.pinnedScore - 1 : Matcher.score(query, Self.target) else { return [] }
        return [ResultItem(id: "cmd:emoji", kind: .command, title: "Emoji", subtitle: "Search emoji",
                           icon: .symbol("face.smiling"), score: score, action: .enterEmojiMode)]
    }
}

public struct EmojiInlineProvider: Provider {
    static let maxInline = 3
    private let store: EmojiStore
    private let aliases: () -> [String: [String]]
    private let recents: () -> [String]
    private let tone: () -> SkinTone

    public init(store: EmojiStore, aliases: @escaping () -> [String: [String]],
                recents: @escaping () -> [String], tone: @escaping () -> SkinTone) {
        self.store = store; self.aliases = aliases; self.recents = recents; self.tone = tone
    }

    /// Only close matches (every word starts a word of the name, a keyword or an alias), at most three,
    /// and never for a one-letter query.
    public func results(for query: Query) -> [ResultItem] {
        guard query.folded.count >= 2 else { return [] }
        let t = tone()
        return store.search(query, aliases: aliases(), recents: recents())
            .prefix(while: { $0.score >= Matcher.prefixScore })
            .prefix(Self.maxInline)
            .map { hit in
                let glyph = hit.emoji.glyph(t)
                return ResultItem(id: "emoji:\(hit.emoji.char)", kind: .emoji, title: hit.emoji.name.capitalizedFirstLetter,
                                  subtitle: "Emoji", icon: .emoji(glyph), score: hit.score * 0.9,
                                  action: .copy(glyph), usageKey: hit.emoji.char)
            }
    }
}

extension String {
    var capitalizedFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}
