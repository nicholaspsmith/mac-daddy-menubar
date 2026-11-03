// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import HotkeyKit
import LauncherCore
import StatusItemKit
import SwiftUI

/// Mac Daddy's Preferences window (menu ▸ Preferences…, ⌘,): the mode, Start at
/// Login, and the launcher with its hotkey, units and emoji options. It
/// replaced the old Settings submenu.
final class SettingsModel: ObservableObject {
    @Published var mode = Mode.load(from: .standard) {
        didSet { if mode != oldValue { onMode(mode) } }
    }
    @Published var launcherEnabled = LauncherPreferences.enabled
    @Published var trigger: Trigger
    @Published var hotkeyError: String?
    @Published var recording = false
    @Published var unitSystem = LauncherPreferences.unitSystem { didSet { LauncherPreferences.unitSystem = unitSystem } }
    @Published var tone = LauncherPreferences.skinTone { didSet { launcher.setSkinTone(tone) } }
    @Published var panelReset = false

    let launcher: Launcher
    private let onMode: (Mode) -> Void
    /// Whether the Settings window is key; set by the controller. A captured key is ignored once
    /// it's false, since the recorder's monitor is app-wide and could otherwise swallow a
    /// keystroke meant for another of our windows (e.g. Emoji Aliases).
    var isWindowKey: () -> Bool = { true }
    private let recorder = TriggerRecorder()
    private var recordTimeout: DispatchWorkItem?
    /// How long an abandoned recording (no key pressed) stays armed before it gives up on its own.
    static let recordTimeoutSeconds: TimeInterval = 10

    init(launcher: Launcher, onMode: @escaping (Mode) -> Void) {
        self.launcher = launcher
        self.onMode = onMode
        trigger = launcher.trigger
    }

    /// Re-reads everything another path may have changed (⌘⇧S in the panel, a failed hotkey).
    func refresh() {
        mode = Mode.load(from: .standard)
        launcherEnabled = launcher.isEnabled
        trigger = launcher.trigger
        hotkeyError = launcher.hotkeyFailure
        tone = LauncherPreferences.skinTone
        panelReset = false
    }

    func setLauncher(_ on: Bool) {
        stopRecording()
        launcher.setEnabled(on)
        launcherEnabled = launcher.isEnabled
        hotkeyError = launcher.hotkeyFailure
    }

    func resetPanelPosition() {
        launcher.resetPanelPosition()
        panelReset = true
    }

    func record() {
        recording = true
        let timeout = DispatchWorkItem { [weak self] in self?.stopRecording() }
        recordTimeout?.cancel()
        recordTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.recordTimeoutSeconds, execute: timeout)
        recorder.start { [weak self] t in
            guard let self else { return }
            self.recordTimeout?.cancel()
            self.recordTimeout = nil
            self.recording = false
            guard self.isWindowKey() else { return }   // the window lost key status mid-capture
            guard HotkeySettings.hasRealModifier(t.modifiers) else { self.hotkeyError = "Add at least one modifier (⌘, ⌥, ⌃ or ⇧)."; return }
            let result = self.launcher.rebind(t)
            self.trigger = result.trigger   // whatever the launcher actually adopted, not necessarily `t`
            self.hotkeyError = result.error
        }
    }

    /// Cancels an in-progress recording: the window closed, resigned key, is being shown again, or
    /// the timeout fired. Leaving the recorder's app-wide monitor installed would otherwise swallow
    /// the next keystroke anywhere in the app.
    func stopRecording() {
        guard recording else { return }
        recordTimeout?.cancel()
        recordTimeout = nil
        recorder.stop()
        recording = false
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let terms = Terms(model.mode)
        PreferencesForm {
            Section("General") {
                Picker(terms.modeMenu, selection: $model.mode) {
                    ForEach(Mode.allCases, id: \.self) { Text(terms.modeName($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                StartAtLoginToggle()
            }
            Section {
                Toggle(terms.launcherToggle, isOn: Binding(get: { model.launcherEnabled }, set: { model.setLauncher($0) }))
                Group {
                    LabeledContent("Hotkey") {
                        HStack {
                            Text(model.recording ? "Press a shortcut…" : TriggerText.describe(model.trigger)).monospaced()
                            Button("Record…") { model.record() }.disabled(model.recording)
                        }
                    }
                    if let err = model.hotkeyError, model.launcherEnabled {
                        Text(err).foregroundStyle(.red).font(.callout)
                    }
                    Picker("Units", selection: $model.unitSystem) {
                        ForEach(UnitSystem.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Emoji skin tone", selection: $model.tone) {
                        ForEach(SkinTone.allCases, id: \.self) { Text("\($0.swatch)  \($0.title)").tag($0) }
                    }
                    LabeledContent("Emoji aliases") { Button("Edit Emoji Aliases…") { model.launcher.openAliases() } }
                    LabeledContent("Panel position") {
                        Button(model.panelReset ? "Reset ✓" : "Reset") { model.resetPanelPosition() }
                    }
                }
                .disabled(!model.launcherEnabled)
            } header: {
                Text(terms.launcher)
            } footer: {
                PreferencesNote("Opens a panel over any app for apps, arithmetic, unit conversions and emoji. ⌘↩ in the panel hands the query to Spotlight, which needs Mac Daddy allowed in Accessibility.")
            }
        }
    }
}

/// The window: StatusItemKit's shared `PreferencesPane` ("Mac Daddy
/// Preferences", Esc / ⌘W close it). A hotkey recording stops when the window
/// is shown again, closes or stops being key, so the recorder's app-wide
/// monitor never swallows a keystroke meant elsewhere.
final class SettingsWindowController {
    let model: SettingsModel
    private let pane: PreferencesPane
    private var resignObserver: NSObjectProtocol?

    init(model: SettingsModel) {
        self.model = model
        pane = PreferencesPane(appName: "Mac Daddy") { SettingsView(model: model) }
        pane.onShow = { [weak model] in
            model?.stopRecording()   // showing again abandons any recording left running
            model?.refresh()
        }
        pane.onClose = { [weak model] in model?.stopRecording() }
        model.isWindowKey = { [weak pane] in pane?.window?.isKeyWindow ?? false }
    }

    deinit { resignObserver.map(NotificationCenter.default.removeObserver) }

    func show() {
        if resignObserver == nil {
            // PreferencesPane is the window's delegate, so watch for resigning key here.
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: pane.makeWindow(), queue: .main
            ) { [weak model] _ in model?.stopRecording() }
        }
        pane.show()
    }
}
