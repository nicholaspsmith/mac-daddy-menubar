// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit

protocol Duty: AnyObject {
    /// Called on the main thread every 5 s; the duty decides whether its own interval has elapsed.
    func tick(now: Date)
    /// The duty's one line in the top-level menu, e.g. "Downloads — swept 2/10/26".
    var title: String { get }
    /// Why the duty is failing, or nil; shown red on its line and atop its submenu.
    var warning: String? { get }
    /// Something waiting on the user (a lost soul, a suggestion): the line goes bold.
    var needsAttention: Bool { get }
    /// Appends the duty's controls (to its submenu, or to the top level for Processes).
    func addMenuItems(to menu: NSMenu)
    /// Called with a flourish when the duty did something visible.
    var onSweep: ((Flourish) -> Void)? { get set }
    /// Called when the duty's state the icon cares about changes (enabled toggled).
    var onChange: (() -> Void)? { get set }
}

extension Duty {
    /// A bold, disabled section title, plus a red "⚠ …" line when the duty is failing.
    func heading(_ title: String, error: String?) -> [NSMenuItem] {
        let h = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        h.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        h.isEnabled = false
        guard let error else { return [h] }
        let e = NSMenuItem(title: "⚠ \(error)", action: nil, keyEquivalent: "")
        e.attributedTitle = NSAttributedString(string: "⚠ \(error)", attributes: [.foregroundColor: NSColor.systemRed])
        e.indentationLevel = 1
        return [h, e]
    }
}

extension Duty {
    var needsAttention: Bool { false }

    /// The top-level line: the title, and the duty's controls as its submenu.
    func sectionItem() -> NSMenuItem {
        let sub = NSMenu()
        addMenuItems(to: sub)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if warning != nil {
            item.attributedTitle = NSAttributedString(string: "⚠ \(title)", attributes: [.foregroundColor: NSColor.systemRed])
        } else if needsAttention {
            item.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        }
        item.submenu = sub
        return item
    }

    /// A red "⚠ …" line for the top of a duty's submenu, when it is failing.
    func warningItems() -> [NSMenuItem] {
        guard let warning else { return [] }
        let e = NSMenuItem(title: "⚠ \(warning)", action: nil, keyEquivalent: "")
        e.attributedTitle = NSAttributedString(string: "⚠ \(warning)", attributes: [.foregroundColor: NSColor.systemRed])
        return [e]
    }
}

/// The current mode's words. Read at each use, so switching mode takes effect
/// on the next menu, notification or window.
var terms: Terms { Terms(Mode.load(from: .standard)) }

func indented(_ item: NSMenuItem) -> NSMenuItem {
    item.indentationLevel = 1
    return item
}
