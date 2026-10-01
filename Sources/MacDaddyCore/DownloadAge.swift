// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

public struct DownloadItem {
    public let url: URL
    public let modified: Date?
    public let added: Date?
    public init(url: URL, modified: Date?, added: Date? = nil) { self.url = url; self.modified = modified; self.added = added }
    /// The later of the modification and added-to-Downloads dates, so a file
    /// with an old mtime (unzipped, copied, AirDropped) counts from its arrival.
    public var date: Date? {
        switch (modified, added) {
        case let (m?, a?): return max(m, a)
        case let (m, a): return m ?? a
        }
    }
}

/// Which top-level Downloads items are old enough for the Trash. An item whose
/// date (see `DownloadItem.date`) cannot be read is kept, as Download Recycler always did.
public enum DownloadAge {
    public static func expired(_ items: [DownloadItem], daysToKeep: Int, now: Date) -> [URL] {
        let cutoff = now.addingTimeInterval(-Double(daysToKeep) * 86_400)
        return items.compactMap { item in
            guard let date = item.date, date < cutoff else { return nil }
            return item.url
        }
    }
}
