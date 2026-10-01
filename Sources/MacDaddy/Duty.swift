// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit

protocol Duty: AnyObject {
    /// Called on the main thread every 5 s; the duty decides whether its own interval has elapsed.
    func tick(now: Date)
    /// Appends a bold heading and its indented items.
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

func indented(_ item: NSMenuItem) -> NSMenuItem {
    item.indentationLevel = 1
    return item
}
