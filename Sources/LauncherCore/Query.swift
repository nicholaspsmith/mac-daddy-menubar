// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// A search string as typed, plus the folded words every matcher compares.
public struct Query: Equatable, Sendable {
    public let raw: String
    /// Lowercased, diacritics and width folded, trimmed.
    public let folded: String
    public let words: [String]

    public init(_ raw: String) {
        self.raw = raw
        folded = Query.fold(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        words = folded.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    public var isEmpty: Bool { words.isEmpty }

    /// The case-, diacritic- and width-insensitive form used on both sides of every match.
    public static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
