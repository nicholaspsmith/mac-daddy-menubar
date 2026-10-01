// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

/// Processes as a share of the per-user limit; nil when either is unknown,
/// so a failed read can never make Mac Daddy sweat.
public func processFraction(count: Int?, limit: Int) -> Double? {
    guard let count, limit > 0 else { return nil }
    return Double(count) / Double(limit)
}
