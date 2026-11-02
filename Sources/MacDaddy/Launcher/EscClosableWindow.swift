// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import AppKit

/// A window Esc closes, for Settings and Emoji Aliases. The launcher panel is a separate class
/// with its own Esc handling (clear the query, back out of emoji mode, then close), so it's
/// unaffected.
final class EscClosableWindow: NSWindow {
    /// Esc reaches here from a text field's field editor, or from a view that doesn't handle it.
    override func cancelOperation(_ sender: Any?) {
        makeFirstResponder(nil)   // end editing first, so an alias field's save-on-blur runs
        performClose(sender)
    }

    /// With nothing (or a non-text control) first responder, Esc arrives as a plain keyDown.
    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad])
        if event.keyCode == 53 && mods.isEmpty {
            cancelOperation(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
