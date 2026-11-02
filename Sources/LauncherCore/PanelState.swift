// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Combine
import Foundation

public enum PanelMode: Equatable, Sendable { case main, emoji }
public enum EscapeOutcome: Equatable, Sendable { case clearedQuery, backToMain, close }

/// Everything the panel shows, and the rules for moving around it. No AppKit here.
public final class PanelState: ObservableObject {
    @Published public private(set) var mode: PanelMode = .main
    @Published public var query: String = "" { didSet { refresh() } }
    @Published public private(set) var results: [ResultItem] = []
    @Published public private(set) var emoji: [EmojiHit] = []
    @Published public private(set) var selection = 0
    @Published public var footerMessage: String?
    public let gridColumns: Int

    private let engine: SearchEngine
    private let emojiSearch: (Query) -> [EmojiHit]

    public init(engine: SearchEngine, gridColumns: Int = 9, emojiSearch: @escaping (Query) -> [EmojiHit]) {
        self.engine = engine
        self.gridColumns = gridColumns
        self.emojiSearch = emojiSearch
    }

    public var itemCount: Int { mode == .main ? results.count : emoji.count }
    public var selectedResult: ResultItem? { mode == .main && selection < results.count ? results[selection] : nil }
    public var selectedEmoji: EmojiHit? { mode == .emoji && selection < emoji.count ? emoji[selection] : nil }
    /// Something typed and nothing found — Mendoza looks puzzled.
    public var isMiss: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty && itemCount == 0 }

    public func refresh() {
        switch mode {
        case .main: results = engine.results(for: query)
        case .emoji: emoji = emojiSearch(Query(query))
        }
        selection = 0
    }

    public func move(_ delta: Int) {
        guard itemCount > 0 else { return }
        selection = min(max(selection + delta, 0), itemCount - 1)
    }

    public func moveGrid(dx: Int, dy: Int) { move(dx + dy * gridColumns) }

    @discardableResult
    public func select(index: Int) -> Bool {
        guard index >= 0, index < itemCount else { return false }
        selection = index
        return true
    }

    public func enterEmojiMode() {
        mode = .emoji
        query = ""
    }

    public func backToMain() {
        mode = .main
        query = ""
    }

    public func escape() -> EscapeOutcome {
        switch mode {
        case .emoji:
            backToMain()
            return .backToMain
        case .main:
            if query.isEmpty { return .close }
            query = ""
            return .clearedQuery
        }
    }

    /// ⌫ on an empty emoji search goes back to the main list.
    public func deleteOnEmpty() -> Bool {
        guard mode == .emoji, query.isEmpty else { return false }
        backToMain()
        return true
    }

    /// Fresh state for each summon.
    public func reset() {
        mode = .main
        footerMessage = nil
        query = ""
        emoji = []
    }
}
