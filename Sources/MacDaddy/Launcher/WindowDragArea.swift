// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import AppKit
import SwiftUI

/// A background that starts moving the panel on a mouseDown — the footer, the margins, and
/// anywhere else nothing in the SwiftUI content above it claims the click first (a row's or a
/// grid cell's own tap gesture, or the field, still wins). `isMovableByWindowBackground` alone is
/// unreliable once a SwiftUI hosting view sits in front of the window background, so this fires
/// the drag itself rather than counting on that.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragCatcherView { DragCatcherView() }
    func updateNSView(_ nsView: DragCatcherView, context: Context) {}
}

final class DragCatcherView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
