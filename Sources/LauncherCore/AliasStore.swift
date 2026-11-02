// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation

public enum AliasStoreError: Error { case fileUnreadable }

/// The user's emoji aliases, `{ "👓": ["nerd"] }`, keyed by base emoji. Hand-editable JSON.
public final class AliasStore {
    public let url: URL
    public private(set) var aliases: [String: [String]] = [:]
    /// Why the file on disk is not in use; the last good copy stays loaded meanwhile.
    public private(set) var loadError: String?
    public var onChange: (() -> Void)?
    private var watcher: DirectoryWatcher?

    public init(url: URL) {
        self.url = url
        reload()
    }

    /// Re-reads the file, notifying only when the aliases or the load error actually changed —
    /// the directory watcher also fires for usage.json writes beside it.
    public func reload() {
        let before = (aliases, loadError)
        load()
        if before != (aliases, loadError) { onChange?() }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: url.path) else {
            aliases = [:]; loadError = nil; return
        }
        do {
            let decoded = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: url))
            aliases = decoded.mapValues(Self.clean).filter { !$0.value.isEmpty }
            loadError = nil
        } catch {
            loadError = "aliases.json could not be read (\(error.localizedDescription)). Using the last good copy; fix or delete the file to edit aliases."
            coreLog.error("aliases.json unreadable: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Replace `emoji`'s aliases (empty removes them). Refuses while the file on disk is unreadable,
    /// so a hand edit with a typo is never overwritten. Re-reads the file first: an in-place edit
    /// changes no directory entry, so the watcher may not have seen it.
    public func setAliases(_ names: [String], for emoji: String) throws {
        load()
        guard loadError == nil else { throw AliasStoreError.fileUnreadable }
        var next = aliases
        let cleaned = Self.clean(names)
        next[emoji] = cleaned.isEmpty ? nil : cleaned
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try AtomicFile.write(enc.encode(next), to: url)
        aliases = next
        onChange?()
    }

    public func startWatching() {
        watcher = DirectoryWatcher(directory: url.deletingLastPathComponent()) { [weak self] in self?.reload() }
    }

    static func clean(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
