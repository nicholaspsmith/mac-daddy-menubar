// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import AppKit
import Carbon.HIToolbox
import HotkeyKit
import LauncherCore

/// A system-wide hotkey through Carbon's RegisterEventHotKey — no Accessibility permission needed.
final class HotkeyService {
    var onPress: (() -> Void)?
    /// Why the hotkey isn't active, for the menu's warning row; nil when it is.
    private(set) var failure: String?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.onPress?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// Register `trigger`, replacing any previous one. Returns the failure reason, if any.
    @discardableResult
    func register(_ trigger: Trigger) -> String? {
        unregister()
        let name = TriggerText.describe(trigger)
        guard case let .key(code, mods) = trigger else {
            failure = "media keys can't open the launcher"; return failure
        }
        if let other = Self.conflictingApp(for: trigger) {
            failure = "\(name) is in use by \(other)"; return failure
        }
        let id = EventHotKeyID(signature: OSType(0x4D43_5248), id: 1)   // 'MCRH'
        let status = RegisterEventHotKey(UInt32(code), Self.carbonModifiers(mods), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        failure = status == noErr ? nil : "\(name) is in use"
        if let failure { launcherLog.error("hotkey: \(failure, privacy: .public) (\(status))") }
        return failure
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    static func carbonModifiers(_ m: Modifiers) -> UInt32 {
        var r: UInt32 = 0
        if m.contains(.command) { r |= UInt32(cmdKey) }
        if m.contains(.option) { r |= UInt32(optionKey) }
        if m.contains(.control) { r |= UInt32(controlKey) }
        if m.contains(.shift) { r |= UInt32(shiftKey) }
        return r
    }

    /// Carbon doesn't reliably report a combination another app holds, so name the known one.
    static func conflictingApp(for trigger: Trigger) -> String? {
        guard trigger == HotkeySettings.defaultTrigger else { return nil }
        let raycast = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.raycast.macos" }
        return raycast ? "Raycast" : nil
    }
}
