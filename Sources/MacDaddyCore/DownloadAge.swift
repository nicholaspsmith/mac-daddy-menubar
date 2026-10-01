// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

public struct DownloadItem {
    public let url: URL
    public let modified: Date?
    public init(url: URL, modified: Date?) { self.url = url; self.modified = modified }
}

/// Which top-level Downloads items are old enough for the Trash. An item whose
/// date cannot be read is kept, as Download Recycler always did.
public enum DownloadAge {
    public static func expired(_ items: [DownloadItem], daysToKeep: Int, now: Date) -> [URL] {
        let cutoff = now.addingTimeInterval(-Double(daysToKeep) * 86_400)
        return items.compactMap { item in
            guard let modified = item.modified, modified < cutoff else { return nil }
            return item.url
        }
    }
}
