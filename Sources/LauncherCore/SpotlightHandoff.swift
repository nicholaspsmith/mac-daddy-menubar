// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics
import Foundation
import HotkeyKit

/// The keyboard shortcut that opens the system Spotlight (on macOS 27, Siri's "Search or Ask")
/// panel, read from where System Settings ▸ Keyboard Shortcuts keeps it.
public enum SpotlightShortcut {
    public static let defaultsDomain = "com.apple.symbolichotkeys"
    public static let hotkeysKey = "AppleSymbolicHotKeys"
    /// AppleSymbolicHotKeys entry "Show Spotlight search".
    public static let entryID = "64"
    /// The launcher holds ⌘Space, so Spotlight lives on ⌥Space when nothing says otherwise.
    public static let fallback = Trigger.key(49, [.option])

    public enum Binding: Equatable, Sendable {
        case key(Trigger)
        /// The shortcut is switched off in System Settings, so posting it would do nothing.
        case disabled
    }

    /// Parse the `AppleSymbolicHotKeys` dictionary. An entry looks like
    /// `{enabled = 1; value = {parameters = (32, 49, 524288); type = standard;}}`: the
    /// parameters are the character (65535 for none), the virtual key code, and the modifiers as
    /// `CGEventFlags` bits. Anything missing or malformed falls back to ⌥Space.
    public static func parse(_ hotkeys: Any?) -> Binding {
        guard let all = hotkeys as? [String: Any], let entry = all[entryID] as? [String: Any] else {
            return .key(fallback)
        }
        if let enabled = number(entry["enabled"]), enabled == 0 { return .disabled }
        guard let value = entry["value"] as? [String: Any],
              let params = value["parameters"] as? [Any], params.count >= 3,
              let code = number(params[1]), let mask = number(params[2]),
              let keyCode = CGKeyCode(exactly: code), keyCode != 0xFFFF, mask >= 0 else {
            return .key(fallback)
        }
        let mods = Modifiers(cgFlags: CGEventFlags(rawValue: UInt64(mask)))
        guard HotkeySettings.hasRealModifier(mods) else { return .key(fallback) }
        return .key(.key(keyCode, mods))
    }

    /// The live binding, read fresh from the preferences domain each time.
    public static func load() -> Binding {
        CFPreferencesAppSynchronize(defaultsDomain as CFString)
        return parse(CFPreferencesCopyAppValue(hotkeysKey as CFString, defaultsDomain as CFString))
    }

    private static func number(_ any: Any?) -> Int? {
        if let n = any as? NSNumber { return n.intValue }
        if let i = any as? Int { return i }
        if let s = any as? String { return Int(s) }
        return nil
    }
}

/// Recognising the Spotlight panel's window in `CGWindowListCopyWindowInfo` output.
public enum SpotlightWindow {
    /// On macOS 27 the panel belongs to Siri (com.apple.campo); earlier systems call it Spotlight.
    public static let ownerNames: Set<String> = ["Siri", "Spotlight"]
    public static let bundleIDs: Set<String> = ["com.apple.campo", "com.apple.Spotlight"]

    /// Whether a window-list entry is the search panel. `bundleID` is looked up by the caller
    /// from the owner PID; either it or the owner name is enough. Layer-0 windows are ordinary
    /// app windows (Spotlight's own Settings, say), not the floating panel.
    public static func isPanel(_ window: [String: Any], bundleID: String?) -> Bool {
        let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        guard layer > 0 else { return false }
        if let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha <= 0 { return false }
        if let bundleID, bundleIDs.contains(bundleID) { return true }
        return ownerNames.contains(window[kCGWindowOwnerName as String] as? String ?? "")
    }

    /// Window numbers of on-screen panels in a window list.
    public static func panelIDs(in list: [[String: Any]], bundleID: (pid_t) -> String?) -> Set<Int> {
        var ids = Set<Int>()
        for w in list {
            let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            guard isPanel(w, bundleID: bundleID(pid)),
                  let n = (w[kCGWindowNumber as String] as? NSNumber)?.intValue else { continue }
            ids.insert(n)
        }
        return ids
    }
}

/// Splitting text into pieces small enough for one `CGEvent.keyboardSetUnicodeString` each
/// (macOS truncates a keyboard event's string at 20 UTF-16 units), never cutting an emoji or a
/// combining sequence in half.
public enum TypingChunks {
    public static let maxUTF16 = 20

    public static func split(_ text: String, maxUTF16: Int = maxUTF16) -> [String] {
        var chunks: [String] = []
        var current = ""
        var size = 0
        for ch in text {
            let n = ch.utf16.count
            if size > 0, size + n > maxUTF16 {
                chunks.append(current)
                current = ""
                size = 0
            }
            current.append(ch)
            size += n
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
