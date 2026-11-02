// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation

public enum ResultAction: Equatable, Sendable {
    case open(URL)
    case reveal(URL)
    case copy(String)
    case enterEmojiMode

    /// Footer wording for this action.
    public var label: String {
        switch self {
        case .open, .enterEmojiMode: return "Open"
        case .reveal: return "Show in Finder"
        case .copy: return "Copy"
        }
    }
}

public enum ResultIcon: Equatable, Sendable {
    case app(URL)
    case emoji(String)
    case symbol(String)   // SF Symbol name
}

public enum ResultKind: Equatable, Sendable { case answer, command, app, emoji }

public struct ResultItem: Equatable, Identifiable, Sendable {
    /// Math and conversion answers sit above everything else.
    public static let pinnedScore = 1000.0

    public let id: String
    public let kind: ResultKind
    public let title: String
    public let subtitle: String
    public let icon: ResultIcon
    public let score: Double
    public let action: ResultAction
    public let alternate: ResultAction?
    /// Footer wording for the ⌥↩ action when `alternate.label` is not specific enough.
    public let alternateLabel: String?
    /// App key or base emoji to record in UsageStore when this item is used.
    public let usageKey: String?

    public init(id: String, kind: ResultKind, title: String, subtitle: String, icon: ResultIcon,
                score: Double, action: ResultAction, alternate: ResultAction? = nil,
                alternateLabel: String? = nil, usageKey: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.subtitle = subtitle; self.icon = icon
        self.score = score; self.action = action; self.alternate = alternate
        self.alternateLabel = alternateLabel; self.usageKey = usageKey
    }

    /// "↩ Open   ⌥↩ Show in Finder"
    public var footerHint: String {
        var s = "↩ \(action.label)"
        if let alternate { s += "   ⌥↩ \(alternateLabel ?? alternate.label)" }
        return s
    }
}

public protocol Provider {
    func results(for query: Query) -> [ResultItem]
}
