// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

public protocol KeyValueStore: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: KeyValueStore {}

public final class MemoryStore: KeyValueStore {
    public var values: [String: Any]
    public init(_ values: [String: Any] = [:]) { self.values = values }
    public func object(forKey defaultName: String) -> Any? { values[defaultName] }
    public func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
}

/// Copies Media Tracking Killer's and Download Recycler's settings into Mac
/// Daddy's namespaced keys, once. Never overwrites a key Mac Daddy already
/// has; a value of the wrong type is skipped (the duty's default applies) and
/// logged. Process Monitor had no settings worth keeping.
///
/// Version 2 (1.1.0): the Godot Reaper became Lost Souls, so `reaper.enabled`
/// carries over to `lostSouls.enabled`.
public enum SettingsMigration {
    public static let currentVersion = 2
    public static let versionKey = "migration.version"
    public static let trackerDomain = "com.nicholaspsmith.MediaTrackingKiller"
    public static let downloadsDomain = "com.nicholaspsmith.DownloadRecycler"
    public static let trackerTargets = ["mediaanalysisd", "mediaanalysisd-access", "photoanalysisd"]

    private enum Kind { case bool, int, date }

    @discardableResult
    public static func run(target: KeyValueStore, tracker: KeyValueStore?, downloads: KeyValueStore?) -> [String] {
        let version = target.object(forKey: versionKey) as? Int ?? 0
        if version >= currentVersion { return [] }
        var log: [String] = []

        func copy(_ source: KeyValueStore?, _ from: String, _ to: String, _ kind: Kind) {
            guard let source, let value = source.object(forKey: from) else { return }
            guard target.object(forKey: to) == nil else { return }
            let ok: Bool
            switch kind {
            case .bool: ok = value is Bool
            case .int: ok = (value as? Int) != nil && !(value is Bool)
            case .date: ok = value is Date
            }
            if ok {
                target.set(value, forKey: to)
                log.append("migrated \(from) → \(to)")
            } else {
                log.append("skipped \(from): unexpected type \(type(of: value)); default applies")
            }
        }

        if version < 1 {
            copy(tracker, "enabled", "tracker.enabled", .bool)
            copy(tracker, "intervalSeconds", "tracker.intervalSeconds", .int)
            for name in trackerTargets { copy(tracker, "target.\(name)", "tracker.target.\(name)", .bool) }
            copy(downloads, "enabled", "downloads.enabled", .bool)
            copy(downloads, "daysToKeep", "downloads.daysToKeep", .int)
            copy(downloads, "lastSweep", "downloads.lastSweep", .date)
        }
        if version < 2 {
            copy(target, "reaper.enabled", "lostSouls.enabled", .bool)
        }

        target.set(currentVersion, forKey: versionKey)
        return log
    }
}
