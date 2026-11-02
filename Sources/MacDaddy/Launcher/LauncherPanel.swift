// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import AppKit

/// A borderless floating panel that takes the keyboard without activating Mac Daddy, so the app
/// you were in stays frontmost and gets focus back the moment the panel closes.
final class LauncherPanel: NSPanel {
    var onResignKey: (() -> Void)?
    var keyEquivalentHandler: ((NSEvent) -> Bool)?

    init(width: CGFloat, height: CGFloat) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { standardWindowButton(b)?.isHidden = true }
        isMovable = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}
