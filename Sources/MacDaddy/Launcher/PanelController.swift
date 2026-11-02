// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import AppKit
import Combine
import HotkeyKit
import LauncherCore
import SwiftUI

final class PanelController: NSObject, NSTextFieldDelegate {
    let state: PanelState
    private let panel: LauncherPanel
    private let field = NSTextField()
    private let performer: ActionPerformer
    private let index: AppIndex
    private let icons = IconCache()
    private let spotlight = SpotlightLauncher()
    private var hosting: NSHostingView<AnyView>!
    private var cancellables = Set<AnyCancellable>()
    private var anchorTop: CGFloat = 0
    private var anchorX: CGFloat = 0
    /// Set while `resize()` moves the panel itself, so that move isn't mistaken for a drag and
    /// saved as a remembered position.
    private var isProgrammaticMove = false
    /// The close that follows a copy; cancelled if the panel is summoned again before it fires.
    private var pendingHide: DispatchWorkItem?
    /// Set while `hide()` runs, so the resignKey that `orderOut` triggers doesn't hide (and notify) twice.
    private var hiding = false
    let emojiUI = EmojiUI()

    var onVisibilityChange: ((Bool) -> Void)?
    var onGrab: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    /// The launcher's own hotkey, so ⌘↩ can refuse to post a Spotlight shortcut that is the same keys.
    var launcherTrigger: () -> Trigger = { HotkeySettings.defaultTrigger }
    /// Called first thing on `show()`, so in-place hand edits of aliases.json are picked up.
    var onShow: (() -> Void)?
    /// Emoji-mode key equivalents (⌘K, ⌘⇧S), installed by Task 15.
    var emojiKeyHandler: ((NSEvent) -> Bool)?
    /// Copy an emoji chosen in the grid, installed by Task 15.
    var activateEmoji: ((EmojiHit) -> Void)?

    init(state: PanelState, performer: ActionPerformer, index: AppIndex) {
        self.state = state
        self.performer = performer
        self.index = index
        panel = LauncherPanel(width: PanelMetrics.width, height: PanelMetrics.fieldHeight + PanelMetrics.footerHeight)
        super.init()
        emojiUI.onClose = { [weak self] in self?.focusField() }

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 24, weight: .light)
        field.placeholderString = Self.mainPlaceholder
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.translatesAutoresizingMaskIntoConstraints = false

        hosting = NSHostingView(rootView: makeBody())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(field)
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 20),
            field.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -20),
            field.topAnchor.constraint(equalTo: effect.topAnchor, constant: 14),
            field.heightAnchor.constraint(equalToConstant: 30),
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor, constant: PanelMetrics.fieldHeight),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        panel.onResignKey = { [weak self] in self?.hide() }
        panel.keyEquivalentHandler = { [weak self] e in self?.handleKeyEquivalent(e) ?? false }
        state.$results.combineLatest(state.$mode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.resize() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            .sink { [weak self] _ in self?.windowMoved() }
            .store(in: &cancellables)
    }

    /// Keep the top edge anchored (so a resize from new results doesn't snap the panel back),
    /// and remember a real drag so the next summon can reopen there.
    private func windowMoved() {
        let f = panel.frame
        anchorTop = f.maxY
        anchorX = f.minX
        guard !isProgrammaticMove else { return }
        PanelPlacement.save(CGPoint(x: f.minX, y: f.maxY), to: .standard)
    }

    static let mainPlaceholder = "Search apps, emoji, math, units…"
    static let emojiPlaceholder = "Search emoji…"

    func makeBody() -> AnyView {
        AnyView(PanelBody(
            state: state, ui: emojiUI, icons: icons,
            onClick: { [weak self] i in self?.activate(index: i, alternate: false) },
            onBack: { [weak self] in self?.state.backToMain(); self?.syncField(); self?.focusField() },
            onPick: { [weak self] hit in self?.activateEmoji?(hit) }))
    }

    func focusField() { panel.makeFirstResponder(field) }

    var isVisible: Bool { panel.isVisible }
    func toggle() { isVisible ? hide() : show() }

    func show() {
        onShow?()
        pendingHide?.cancel()
        pendingHide = nil
        state.reset()
        emojiUI.editing = nil
        syncField()
        guard let (top, x) = placement() else { return }
        anchorTop = top
        anchorX = x
        resize()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        onVisibilityChange?(true)
    }

    /// Where to open: a remembered drag position if it's still on a connected screen, else
    /// centered a third down on the screen under the mouse.
    private func placement() -> (top: CGFloat, x: CGFloat)? {
        let screens = NSScreen.screens.map(\.visibleFrame)
        if let saved = PanelPlacement.decide(saved: PanelPlacement.load(from: .standard), screens: screens) {
            return (saved.y, saved.x)
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return nil }
        return (vf.maxY - vf.height / 3 + PanelMetrics.fieldHeight / 2, vf.midX - PanelMetrics.width / 2)
    }

    func hide() {
        guard panel.isVisible, !hiding else { return }
        hiding = true
        defer { hiding = false }
        pendingHide?.cancel()
        pendingHide = nil
        panel.orderOut(nil)
        onVisibilityChange?(false)
    }

    func resize() {
        let body: CGFloat
        if state.mode == .emoji {
            body = PanelMetrics.emojiBodyHeight
        } else {
            let rows = min(state.results.count, PanelMetrics.maxRows)
            body = rows == 0 ? 0 : CGFloat(rows) * PanelMetrics.rowHeight + 9
        }
        let h = PanelMetrics.fieldHeight + body + PanelMetrics.footerHeight
        isProgrammaticMove = true
        panel.setFrame(NSRect(x: anchorX, y: anchorTop - h, width: PanelMetrics.width, height: h), display: true)
        isProgrammaticMove = false
    }

    /// Put the field's text and placeholder in step with the state (after mode changes).
    func syncField() {
        field.stringValue = state.query
        field.placeholderString = state.mode == .main ? Self.mainPlaceholder : Self.emojiPlaceholder
    }

    // MARK: - Keys

    func controlTextDidChange(_ obj: Notification) {
        state.footerMessage = nil
        state.query = field.stringValue
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        let grid = state.mode == .emoji
        switch sel {
        case #selector(NSResponder.moveUp(_:)):
            grid ? state.moveGrid(dx: 0, dy: -1) : state.move(-1); return true
        case #selector(NSResponder.moveDown(_:)):
            grid ? state.moveGrid(dx: 0, dy: 1) : state.move(1); return true
        case #selector(NSResponder.moveLeft(_:)) where grid:
            state.moveGrid(dx: -1, dy: 0); return true
        case #selector(NSResponder.moveRight(_:)) where grid:
            state.moveGrid(dx: 1, dy: 0); return true
        case #selector(NSResponder.insertNewline(_:)):
            activateSelection(alternate: false); return true
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):   // ⌥↩
            activateSelection(alternate: true); return true
        case #selector(NSResponder.cancelOperation(_:)):
            if emojiUI.editing != nil { emojiUI.editing = nil; focusField(); return true }
            switch state.escape() {
            case .close: hide()
            case .clearedQuery, .backToMain: syncField()
            }
            return true
        case #selector(NSResponder.deleteBackward(_:)):
            if state.deleteOnEmpty() { syncField(); return true }
            return false
        default:
            return false
        }
    }

    func handleKeyEquivalent(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command) else { return false }
        if (e.keyCode == 36 || e.keyCode == 76) && !mods.contains(.shift) {   // ⌘↩
            if state.mode == .main { searchInSpotlight() } else { activateSelection(alternate: true) }
            return true
        }
        if e.keyCode == 43 && !mods.contains(.shift) {                          // ⌘,
            hide(); onOpenSettings?(); return true
        }
        if e.keyCode == 13 && !mods.contains(.shift) {                          // ⌘W
            hide(); return true   // not the main menu's Close, which would close() the panel behind hide()'s back
        }
        if state.mode == .main, !mods.contains(.shift), let n = Self.digitKeyCodes.firstIndex(of: e.keyCode) {   // ⌘1–9
            activate(index: n, alternate: false); return true
        }
        if state.mode == .emoji, let handler = emojiKeyHandler, handler(e) { return true }
        return false
    }

    /// ANSI key codes for the digit row 1–9. Key codes, not characters, so ⌘1–9 also work on
    /// layouts (AZERTY) where the unshifted digit keys type something else.
    static let digitKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    // MARK: - Actions

    func activateSelection(alternate: Bool) {
        if state.mode == .emoji {
            if let hit = state.selectedEmoji { activateEmoji?(hit) }
            return
        }
        activate(index: state.selection, alternate: alternate)
    }

    func activate(index i: Int, alternate: Bool) {
        guard state.mode == .main, state.select(index: i), let item = state.selectedResult else { return }
        guard let action = alternate ? item.alternate : item.action else { return }
        switch action {
        case .enterEmojiMode:
            state.enterEmojiMode()
            syncField()
        case .open(let url):
            if performer.open(url, usageKey: item.usageKey) {
                onGrab?()
                hide()
            } else {
                state.footerMessage = "Couldn't open \(item.title)"
                index.rebuild()
                state.refresh()   // drop the app that's gone; refresh leaves the footer message alone
            }
        case .reveal(let url):
            performer.reveal(url)
            hide()
        case .copy(let text):
            performer.copy(text)
            if item.kind == .emoji, let base = item.usageKey { performer.recordEmoji(base) }
            flashCopied()
        }
    }

    /// ⌘↩: close the panel and hand exactly what's typed to the system Spotlight panel. If that
    /// can't happen (no Accessibility, shortcut off, panel never shows) the query stays here with
    /// the reason in the footer.
    func searchInSpotlight() {
        let query = state.query
        switch spotlight.preflight(launcherTrigger: launcherTrigger()) {
        case .failure(let failure):
            state.footerMessage = failure.message
        case .success(let shortcut):
            hide()
            spotlight.open(with: shortcut, typing: query) { [weak self] failure in
                guard let self, let failure else { return }
                self.show()
                self.state.query = query
                self.syncField()
                self.state.footerMessage = failure.message
            }
        }
    }

    func flashCopied() {
        state.footerMessage = "Copied"
        onGrab?()
        pendingHide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingHide = nil
            self?.hide()
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
