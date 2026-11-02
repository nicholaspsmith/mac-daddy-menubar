// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import AppKit
import CoreGraphics
import HotkeyKit
import LauncherCore

/// ⌘↩: hand the query to the system Spotlight panel (Siri's "Search or Ask" on macOS 27). Posts
/// Spotlight's own shortcut, waits for its window, then types the query as Unicode keyboard
/// events — never Return, so the choice stays with you. Posting events needs Accessibility.
final class SpotlightLauncher {
    enum Failure: Error, Equatable {
        case notTrusted
        case shortcutOff
        case sameAsLauncher(String)
        case panelDidNotAppear

        var message: String {
            switch self {
            case .notTrusted: return "Allow Mac Daddy in Accessibility to search in Spotlight"
            case .shortcutOff: return "Spotlight's shortcut is off in Keyboard Shortcuts"
            case .sameAsLauncher(let keys): return "Spotlight is on \(keys) too, so the launcher can't open it"
            case .panelDidNotAppear: return "Spotlight didn't open"
            }
        }
    }

    /// How long to wait for the panel's window to come on screen.
    static let appearTimeout: TimeInterval = 3
    /// How long to wait for ⌘ (still held from ⌘↩) to come up before posting anything.
    static let releaseTimeout: TimeInterval = 1.0

    private let queue = DispatchQueue(label: "com.nicholaspsmith.MacDaddy.spotlight")
    private var busy = false

    /// Checks that can fail before the panel closes, so a refusal leaves everything in place.
    func preflight(launcherTrigger: Trigger) -> Result<Trigger, Failure> {
        guard CGPreflightPostEventAccess() else {
            CGRequestPostEventAccess()   // the system prompt that leads to Accessibility
            return .failure(.notTrusted)
        }
        switch SpotlightShortcut.load() {
        case .disabled:
            return .failure(.shortcutOff)
        case .key(let trigger):
            if trigger == launcherTrigger { return .failure(.sameAsLauncher(TriggerText.describe(trigger))) }
            return .success(trigger)
        }
    }

    /// Open the panel and type `query` into it; `completion` runs on the main queue with nil on
    /// success. Call after `preflight` succeeded and the launcher panel has closed.
    func open(with shortcut: Trigger, typing query: String, completion: @escaping (Failure?) -> Void) {
        guard !busy, case let .key(code, mods) = shortcut else { return }
        busy = true
        queue.async {
            let result = Self.run(code: code, flags: mods.cgFlags, query: query)
            DispatchQueue.main.async {
                self.busy = false
                completion(result)
            }
        }
    }

    // MARK: - Background work

    private static func run(code: CGKeyCode, flags: CGEventFlags, query: String) -> Failure? {
        waitForModifiersUp()
        let before = panelWindows()
        if before.isEmpty {
            post(code, flags: flags)
            guard waitForPanel(excluding: []) else {
                launcherLog.error("spotlight: panel did not appear within \(appearTimeout)s")
                return .panelDidNotAppear
            }
            // The window is up a beat before its field takes the keyboard.
            usleep(150_000)
        }
        // Already open (left up from before): type straight into it, since posting the shortcut
        // again would close it.
        type(query)
        return nil
    }

    /// The user is still holding ⌘ from ⌘↩; typed letters with ⌘ down would be shortcuts.
    private static func waitForModifiersUp() {
        let deadline = Date().addingTimeInterval(releaseTimeout)
        let held: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        while Date() < deadline, !CGEventSource.flagsState(.hidSystemState).intersection(held).isEmpty {
            usleep(10_000)
        }
    }

    private static func panelWindows() -> Set<Int> {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return SpotlightWindow.panelIDs(in: list) { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
    }

    private static func waitForPanel(excluding before: Set<Int>) -> Bool {
        let deadline = Date().addingTimeInterval(appearTimeout)
        repeat {
            if !panelWindows().subtracting(before).isEmpty { return true }
            usleep(20_000)
        } while Date() < deadline
        return false
    }

    private static func post(_ code: CGKeyCode, flags: CGEventFlags, unicode: String? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            if let unicode {
                let units = Array(unicode.utf16)
                e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            }
            e.post(tap: .cghidEventTap)
            usleep(15_000)   // a key-up landing on top of its key-down is sometimes dropped
        }
    }

    /// Type text as Unicode keyboard events, so emoji, punctuation and any layout come through
    /// exactly. Key code 0 carries the string; the receiving field reads the string, not the key.
    private static func type(_ text: String) {
        for chunk in TypingChunks.split(text) { post(0, flags: [], unicode: chunk) }
    }
}
