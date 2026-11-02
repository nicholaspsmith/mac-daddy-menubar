// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import HotkeyKit
import LauncherCore
import os

let launcherLog = Logger(subsystem: "com.nicholaspsmith.MacDaddy", category: "launcher")

enum LauncherPreferences {
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: LauncherKeys.enabled) }
        set { UserDefaults.standard.set(newValue, forKey: LauncherKeys.enabled) }
    }
    static var unitSystem: UnitSystem {
        get { UnitSystem(rawValue: UserDefaults.standard.string(forKey: LauncherKeys.unitSystem) ?? "") ?? .usImperial }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: LauncherKeys.unitSystem) }
    }
    static var skinTone: SkinTone {
        get { SkinTone(rawValue: UserDefaults.standard.integer(forKey: LauncherKeys.skinTone)) ?? .none }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: LauncherKeys.skinTone) }
    }
}

/// The launcher, formerly Menu Crane: a ⌘Space panel for apps, arithmetic,
/// unit conversions and emoji. Off by default; Settings… turns it on and off.
/// Nothing is built until it is first turned on, and turning it off releases
/// the hotkey and stops watching the Applications folders.
final class Launcher {
    private let hotkey = HotkeyService()
    private(set) var trigger = HotkeySettings.load(from: .standard)
    private var services: Services?
    /// Opens Mac Daddy's Settings window (⌘, in the panel).
    var onOpenSettings: (() -> Void)?

    private final class Services {
        let usage: UsageStore
        let aliases: AliasStore
        let emojiStore: EmojiStore?
        let appIndex: AppIndex
        let appWatcher: FSEventsWatcher
        let panel: PanelController
        let aliasesWindow: AliasesWindowController?

        init(launcher: Launcher) {
            let dir = AppSupport.directory
            usage = UsageStore(url: dir.appending(path: "usage.json"))
            aliases = AliasStore(url: dir.appending(path: "aliases.json"))
            aliases.startWatching()
            if let url = Bundle.main.url(forResource: "emoji", withExtension: "json"),
               let data = try? Data(contentsOf: url), let store = try? EmojiStore(data: data) {
                emojiStore = store
            } else {
                emojiStore = nil
                launcherLog.fault("emoji.json missing from the bundle; emoji disabled")
            }
            let appIndex = AppIndex()
            self.appIndex = appIndex
            appWatcher = FSEventsWatcher(paths: AppIndex.defaultRoots.map(\.path)) { appIndex.rebuild() }

            var providers: [Provider] = [
                CalculatorProvider(),
                ConverterProvider(system: { LauncherPreferences.unitSystem }),
                AppProvider(index: appIndex, usage: usage),
            ]
            let usage = usage, aliases = aliases
            if let store = emojiStore {
                providers.insert(EmojiCommandProvider(), at: 2)
                providers.append(EmojiInlineProvider(store: store, aliases: { aliases.aliases },
                                                     recents: { usage.recentEmoji },
                                                     tone: { LauncherPreferences.skinTone }))
            }
            let emojiStore = emojiStore
            let state = PanelState(engine: SearchEngine(providers: providers)) { q in
                guard let store = emojiStore else { return [] }
                return store.search(q, aliases: aliases.aliases, recents: usage.recentEmoji)
            }
            let panel = PanelController(state: state, performer: ActionPerformer(usage: usage), index: appIndex)
            self.panel = panel
            panel.emojiUI.tone = LauncherPreferences.skinTone
            panel.onShow = { aliases.reload() }

            AliasEditorView.aliasesFor = { c in aliases.aliases[c] ?? [] }
            AliasEditorView.save = { names, c in try aliases.setAliases(names, for: c) }
            panel.activateEmoji = { [weak panel] hit in
                guard let panel else { return }
                let performer = ActionPerformer(usage: usage)
                performer.copy(hit.emoji.glyph(panel.emojiUI.tone))
                performer.recordEmoji(hit.emoji.char)
                panel.flashCopied()
            }
            panel.emojiKeyHandler = { [weak panel] e in
                guard let panel else { return false }
                let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if e.keyCode == 40 && !mods.contains(.shift), panel.emojiUI.editing == nil,
                   let hit = panel.state.selectedEmoji {                                                // ⌘K
                    panel.emojiUI.editing = hit.emoji
                    return true
                }
                if e.keyCode == 1 && mods.contains(.shift) {                                            // ⌘⇧S
                    let next = panel.emojiUI.tone.next
                    panel.emojiUI.tone = next
                    LauncherPreferences.skinTone = next
                    panel.state.footerMessage = "Skin tone: \(next.title) \(next.swatch)"
                    return true
                }
                return false
            }
            aliases.onChange = { [weak panel] in panel?.state.refresh() }
            aliasesWindow = emojiStore.map { AliasesWindowController(model: AliasesModel(store: $0, aliasStore: aliases, usage: usage)) }
            panel.onOpenSettings = { [weak launcher] in launcher?.onOpenSettings?() }
            panel.launcherTrigger = { [weak launcher] in launcher?.trigger ?? HotkeySettings.defaultTrigger }
        }
    }

    init() {
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    var isEnabled: Bool { LauncherPreferences.enabled }
    /// Why the hotkey isn't active, while the launcher is on.
    var hotkeyFailure: String? { isEnabled ? hotkey.failure : nil }

    /// Starts the launcher if it is turned on. Called once the Menu Crane
    /// cut-over has finished, so ⌘Space is free.
    func start() {
        guard isEnabled else { return }
        let s = services ?? Services(launcher: self)
        services = s
        s.appWatcher.start()
        hotkey.register(trigger)
        launcherLog.notice("launcher on: \(TriggerText.describe(self.trigger), privacy: .public)")
    }

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        LauncherPreferences.enabled = on
        if on {
            start()
        } else {
            hotkey.unregister()
            services?.panel.hide()
            services?.appWatcher.stop()
            launcherLog.notice("launcher off")
        }
    }

    /// Every poll: retry a hotkey another app was holding (e.g. right after Raycast quits).
    func poll() {
        if isEnabled, hotkey.failure != nil { hotkey.register(trigger) }
    }

    func toggle() {
        guard isEnabled, let panel = services?.panel else { return }
        panel.toggle()
    }

    /// Registers `t`; on failure the previous hotkey stays active. Returns
    /// what is actually active and any message for Settings.
    func rebind(_ t: Trigger) -> (trigger: Trigger, error: String?) {
        let previous = trigger
        guard isEnabled else {
            HotkeySettings.save(t, to: .standard)
            trigger = t
            return (t, nil)
        }
        let failure = hotkey.register(t)
        if failure == nil {
            HotkeySettings.save(t, to: .standard)
        } else {
            hotkey.register(previous)   // restore the hotkey that was working
        }
        let decision = HotkeyRebind.decide(new: t, failure: failure, previous: previous)
        trigger = decision.trigger
        return (decision.trigger, decision.message)
    }

    func setSkinTone(_ t: SkinTone) {
        LauncherPreferences.skinTone = t
        services?.panel.emojiUI.tone = t
    }

    /// Opens the Emoji Aliases window, building the launcher's stores if it has never been on.
    func openAliases() {
        let s = services ?? Services(launcher: self)
        services = s
        s.aliasesWindow?.show()
    }

    /// Forget the dragged-to position; the next summon opens centered a third
    /// down the screen under the mouse.
    func resetPanelPosition() { PanelPlacement.clear(from: .standard) }
}
