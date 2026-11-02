// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import AppKit

final class IconCache {
    private var cache: [URL: NSImage] = [:]
    func icon(for url: URL) -> NSImage {
        if let hit = cache[url] { return hit }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 32, height: 32)
        cache[url] = img
        return img
    }
}
