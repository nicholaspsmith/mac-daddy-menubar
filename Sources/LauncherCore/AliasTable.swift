// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation

public struct AliasRow: Identifiable, Equatable, Sendable {
    public var id: String { char }
    public let char: String
    public let name: String
    public let group: String
    public let aliases: [String]
    public var aliasText: String { aliases.joined(separator: ", ") }
}

public enum AliasTable {
    /// Rows for the Emoji Aliases window: ranked by `search` when given (same matcher as the
    /// picker), else Unicode order; then narrowed by group and the two toggles.
    public static func rows(store: EmojiStore, aliases: [String: [String]], recents: [String],
                            search: String, group: String?, onlyWithAliases: Bool, onlyRecent: Bool) -> [AliasRow] {
        let q = Query(search)
        let ordered: [Emoji] = q.isEmpty ? store.all : store.search(q, aliases: aliases, recents: []).map(\.emoji)
        let recentSet = Set(recents)
        return ordered
            .filter { group == nil || $0.group == group }
            .filter { !onlyWithAliases || !(aliases[$0.char] ?? []).isEmpty }
            .filter { !onlyRecent || recentSet.contains($0.char) }
            .map { AliasRow(char: $0.char, name: $0.name, group: $0.group, aliases: aliases[$0.char] ?? []) }
    }
}
