// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import AppKit
import LauncherCore

final class ActionPerformer {
    private let usage: UsageStore
    init(usage: UsageStore) { self.usage = usage }

    /// false when the app is no longer at `url` (deleted or moved since indexing).
    func open(_ url: URL, usageKey: String?) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { launcherLog.error("open \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)") }
        }
        if let usageKey { usage.recordLaunch(usageKey) }
        return true
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    func recordEmoji(_ base: String) { usage.recordEmoji(base) }
}
