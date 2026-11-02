// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics
import Foundation
import HotkeyKit

public enum HotkeySettings {
    public static let keyCodeKey = "launcher.hotkeyKeyCode"
    public static let modifiersKey = "launcher.hotkeyModifiers"
    public static let defaultTrigger = Trigger.key(49, [.command])   // ⌘Space

    /// The saved hotkey; a bare key with no real modifier is refused (it would eat normal
    /// typing), as is a key code that doesn't fit a `CGKeyCode`.
    public static func load(from defaults: UserDefaults) -> Trigger {
        guard defaults.object(forKey: keyCodeKey) != nil,
              let code = CGKeyCode(exactly: defaults.integer(forKey: keyCodeKey)) else { return defaultTrigger }
        let mods = Modifiers(rawValue: defaults.integer(forKey: modifiersKey))
        guard hasRealModifier(mods) else { return defaultTrigger }
        return .key(code, mods)
    }

    /// Whether `mods` holds ⌘, ⌥, ⌃ or ⇧. fn alone doesn't count: macOS sets it on the arrows,
    /// Home/End, PgUp/PgDn and forward-delete, so "fn+↓" would register a bare ↓ system-wide.
    public static func hasRealModifier(_ mods: Modifiers) -> Bool { !mods.subtracting(.fn).isEmpty }

    public static func save(_ trigger: Trigger, to defaults: UserDefaults) {
        guard case let .key(code, mods) = trigger else { return }
        defaults.set(Int(code), forKey: keyCodeKey)
        defaults.set(mods.rawValue, forKey: modifiersKey)
    }
}

public enum TriggerText {
    public static func describe(_ trigger: Trigger) -> String {
        switch trigger {
        case let .key(code, mods): return symbols(mods) + (names[code] ?? "Key \(code)")
        case let .mediaKey(key, mods): return symbols(mods) + "Media \(key)"
        }
    }

    static func symbols(_ m: Modifiers) -> String {
        (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "")
            + (m.contains(.shift) ? "⇧" : "") + (m.contains(.command) ? "⌘" : "")
    }

    static let names: [CGKeyCode: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}

/// The outcome of attempting to register a newly recorded trigger: what's actually active
/// afterward, and what to tell the user. Pure (no Carbon call), so the rollback logic is
/// unit-testable: the caller has already re-registered `previous` when `failure` is non-nil, and
/// this only decides whether the *active* trigger is the new one or the one still working — the
/// single source of truth callers (both `App` and the Settings UI) should adopt.
public enum HotkeyRebind {
    public static func decide(new: Trigger, failure: String?, previous: Trigger) -> (trigger: Trigger, message: String?) {
        guard let failure else { return (new, nil) }
        return (previous, "\(failure) — kept \(TriggerText.describe(previous))")
    }
}
