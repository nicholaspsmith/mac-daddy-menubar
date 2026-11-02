// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// The launcher's own settings keys in Mac Daddy's domain.
public enum LauncherKeys {
    /// Bool, default off. The Menu Crane migration turns it on for someone who used Menu Crane.
    public static let enabled = "launcher.enabled"
    public static let unitSystem = "launcher.unitSystem"
    public static let skinTone = "launcher.skinTone"
}

/// Menu Crane's settings and files, brought into Mac Daddy once, after the
/// cut-over has quit it (so the snapshot is final).
///
/// Each old key moves to its `launcher.` name, only where Mac Daddy has no
/// value of its own. Menu Crane's `IconStyle` and status-item position stay
/// behind (they described its own menu-bar icon). `aliases.json` and
/// `usage.json` are copied, never moved, and never over a file already
/// there. The old domain and folder are left alone: they go with Menu Crane.
public enum MenuCraneMigration {
    /// Set in Mac Daddy's domain once the copy has run.
    public static let doneKey = "launcher.migratedFromMenuCrane"
    public static let oldDomain = "com.nicholaspsmith.MenuCrane"
    public static let files = ["aliases.json", "usage.json"]

    /// Menu Crane's key → Mac Daddy's. Every key Menu Crane's code read
    /// (HotkeySettings, PanelPlacement, Preferences), checked against
    /// `defaults read com.nicholaspsmith.MenuCrane` (2026-11-02).
    public static let keyMap: [String: String] = [
        "HotkeyKeyCode": HotkeySettings.keyCodeKey,
        "HotkeyModifiers": HotkeySettings.modifiersKey,
        "PanelX": PanelPlacement.xKey,
        "PanelTop": PanelPlacement.topKey,
        "UnitSystem": LauncherKeys.unitSystem,
        "SkinTone": LauncherKeys.skinTone,
    ]

    public static var oldSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/MenuCrane")
    }

    /// Keys to write into Mac Daddy's domain. `old` is Menu Crane's domain;
    /// `existing` the keys Mac Daddy already has; `installed` whether a Menu
    /// Crane bundle was found. Someone who used Menu Crane (it was installed,
    /// or left settings behind) gets the launcher switched on, unless they
    /// already chose.
    public static func values(old: [String: Any], existing: Set<String>, installed: Bool) -> [String: Any] {
        var result: [String: Any] = [:]
        for (from, to) in keyMap where !existing.contains(to) {
            if let value = old[from] { result[to] = value }
        }
        if (installed || !old.isEmpty), !existing.contains(LauncherKeys.enabled) {
            result[LauncherKeys.enabled] = true
        }
        return result
    }

    /// Runs the copy into `defaults` (whose persistent domain is `domain`)
    /// unless `doneKey` is already set there, then sets it. Returns the keys
    /// written, or nil when it had already run.
    @discardableResult
    public static func applyOnce(old: [String: Any], installed: Bool, to defaults: UserDefaults, domain: String) -> [String]? {
        let existing = defaults.persistentDomain(forName: domain) ?? [:]
        guard existing[doneKey] as? Bool != true else { return nil }
        let new = values(old: old, existing: Set(existing.keys), installed: installed)
        for (key, value) in new { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: doneKey)
        return new.keys.sorted()
    }

    /// Copies Menu Crane's data files into `to`, skipping any already there.
    /// Returns the names copied.
    @discardableResult
    public static func copyFiles(from: URL, to: URL, fileManager fm: FileManager = .default) -> [String] {
        var copied: [String] = []
        for name in files {
            let src = from.appending(path: name), dst = to.appending(path: name)
            guard fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) else { continue }
            do {
                try fm.createDirectory(at: to, withIntermediateDirectories: true)
                try fm.copyItem(at: src, to: dst)
                copied.append(name)
            } catch {
                coreLog.error("copy \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return copied
    }

    /// One domain's own keys for the current user, any host. Unlike
    /// `UserDefaults(suiteName:).dictionaryRepresentation()`, nothing from the
    /// global or registration domains is mixed in.
    public static func readDomain(_ domain: String) -> [String: Any] {
        let all = CFPreferencesCopyMultiple(nil, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return all as? [String: Any] ?? [:]
    }
}
