// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation

public final class SearchEngine {
    private let providers: [Provider]
    public init(providers: [Provider]) { self.providers = providers }

    /// Every provider's results for `raw`, best first; equal scores keep provider order.
    public func results(for raw: String, limit: Int = 50) -> [ResultItem] {
        let query = Query(raw)
        guard !query.isEmpty else { return [] }
        return providers.flatMap { $0.results(for: query) }
            .enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .prefix(limit)
            .map(\.element)
    }
}
