// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// App launch counts for frecency, and recently used emoji (base emoji, newest first).
public final class UsageStore {
    public static let maxRecentEmoji = 24

    struct AppUse: Codable { var count: Int; var last: Date }
    struct Snapshot: Codable { var apps: [String: AppUse] = [:]; var recentEmoji: [String] = [] }

    private let url: URL
    private let now: () -> Date
    private var snap: Snapshot

    public init(url: URL, now: @escaping () -> Date = Date.init) {
        self.url = url
        self.now = now
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601

        // Check if file exists first
        guard FileManager.default.fileExists(atPath: url.path) else {
            snap = Snapshot()
            return
        }

        // File exists, try to read it
        do {
            let data = try Data(contentsOf: url)
            snap = try dec.decode(Snapshot.self, from: data)
        } catch {
            coreLog.error("usage.json unreadable, starting fresh: \(error.localizedDescription, privacy: .public)")
            snap = Snapshot()
        }
    }

    public var recentEmoji: [String] { snap.recentEmoji }

    public func recordLaunch(_ key: String) {
        var use = snap.apps[key] ?? AppUse(count: 0, last: now())
        use.count += 1
        use.last = now()
        snap.apps[key] = use
        save()
    }

    public func recordEmoji(_ base: String) {
        snap.recentEmoji.removeAll { $0 == base }
        snap.recentEmoji.insert(base, at: 0)
        snap.recentEmoji = Array(snap.recentEmoji.prefix(Self.maxRecentEmoji))
        save()
    }

    /// 0…1.5: grows with log2 of launches, halves roughly every three weeks of disuse.
    public func boost(for key: String) -> Double {
        guard let use = snap.apps[key] else { return 0 }
        let days = max(0, now().timeIntervalSince(use.last) / 86_400)
        return min(1.5, log2(1 + Double(use.count)) * 0.3) * exp(-days / 30)
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try AtomicFile.write(enc.encode(snap), to: url) }
        catch { coreLog.error("usage.json not saved: \(error.localizedDescription, privacy: .public)") }
    }
}
