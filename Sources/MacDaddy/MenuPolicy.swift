// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import StatusItemKit

/// How the menu behaves when clicked (issue #41, StatusItemKit's shared rows):
///
/// - Picking an option (Kill Now, an interval, a threshold, Pimp Slap on a hoe)
///   applies it and leaves the menu open, its tick or line updated in place.
/// - Quit, "…" items, and items marked `closing` close it: they open a window,
///   the launcher panel, another app, or an alert, none of which can take the
///   focus (or run, for an alert) while the menu tracks.
/// - A row you can't click (a heading, a stat, a note) is disabled, so it draws
///   grey, whenever it is added.
enum MenuPolicy {
    static let closesMenu = NSUserInterfaceItemIdentifier("com.nicholaspsmith.MacDaddy.closesMenu")

    /// Marks `item` as one that closes the menu though its title has no "…".
    @discardableResult
    static func closing(_ item: NSMenuItem) -> NSMenuItem {
        item.identifier = closesMenu
        return item
    }

    /// The last step of building a menu, or a submenu replaced while it is
    /// open: action items keep the menu open, read-only rows go grey.
    static func finish(_ items: [NSMenuItem]) {
        for item in items where !item.isSeparatorItem {
            if let sub = item.submenu { finish(sub.items); continue }
            if item.action == nil {
                // Disabled by hand: AppKit's validation would too, but only as
                // the menu opens, not for a row added while it is open.
                item.isEnabled = false
                continue
            }
            guard item.identifier != closesMenu else { continue }
            KeepOpenMenu.apply(to: [item])
        }
    }

    /// A row whose subject is gone (ended, ignored, deleted) while the menu is
    /// open: its title says so, and nothing under it can be clicked any more.
    /// Its submenu, if open, stays up, greyed out.
    static func retire(_ row: NSMenuItem, note: String) {
        row.attributedTitle = nil
        row.title = "\(row.title) — \(note)"
        if row.submenu == nil {
            disable(row)
        } else {
            disableAll(in: row.submenu!)
        }
        row.view?.needsDisplay = true
    }

    private static func disableAll(in menu: NSMenu) {
        for item in menu.items where !item.isSeparatorItem {
            if let sub = item.submenu { disableAll(in: sub) } else { disable(item) }
        }
    }

    /// Off for good: without an action, AppKit's validation keeps it off too.
    private static func disable(_ item: NSMenuItem) {
        if let toggle = ToggleMenuItem.view(of: item) { toggle.isEnabled = false }
        item.action = nil
        item.isEnabled = false
        item.view?.needsDisplay = true
    }
}

extension NSMenuItem {
    /// The item `levels` menus up that opens the submenu this item sits in:
    /// 1 is the item whose submenu holds this one.
    func ancestor(_ levels: Int) -> NSMenuItem? {
        var item: NSMenuItem? = self
        for _ in 0..<levels { item = item?.menu?.parentItem }
        return item
    }
}
