// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics
import Foundation

/// Where the panel remembers being dragged to, and the rule for using it again.
public enum PanelPlacement {
    public static let xKey = "launcher.panelX"
    public static let topKey = "launcher.panelTop"

    /// The remembered top-left, if a drag ever saved one.
    public static func load(from defaults: UserDefaults) -> CGPoint? {
        guard defaults.object(forKey: xKey) != nil, defaults.object(forKey: topKey) != nil else { return nil }
        return CGPoint(x: defaults.double(forKey: xKey), y: defaults.double(forKey: topKey))
    }

    public static func save(_ point: CGPoint, to defaults: UserDefaults) {
        defaults.set(Double(point.x), forKey: xKey)
        defaults.set(Double(point.y), forKey: topKey)
    }

    /// Forget the remembered position (menu ▸ Reset Panel Position).
    public static func clear(from defaults: UserDefaults) {
        defaults.removeObject(forKey: xKey)
        defaults.removeObject(forKey: topKey)
    }

    /// The panel's width and its smallest height (search field + footer, no results).
    public static let panelWidth: CGFloat = 680
    public static let minPanelHeight: CGFloat = 56 + 28

    /// A remembered top-left is used only while the panel it places — `panelWidth` wide and at
    /// least `minPanelHeight` tall, hanging down from that point — overlaps a currently
    /// connected screen's visible frame; otherwise (or if nothing was ever saved) the caller
    /// falls back to its own default placement. Checking the panel's rect rather than the point
    /// alone rejects a point on a screen's bottom edge (the panel would sit entirely below it).
    /// Pure — no AppKit, so this is unit-testable without a real screen.
    public static func decide(saved: CGPoint?, screens: [CGRect]) -> CGPoint? {
        guard let saved else { return nil }
        let panel = CGRect(x: saved.x, y: saved.y - minPanelHeight, width: panelWidth, height: minPanelHeight)
        guard screens.contains(where: { $0.intersects(panel) }) else { return nil }
        return saved
    }
}
