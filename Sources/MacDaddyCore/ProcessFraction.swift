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

/// At or above this share a failed read keeps the last good fraction.
public let holdFractionAtOrAbove = 0.85

/// The fraction to show given this poll's reading and the last good one. A
/// read that fails at the limit (where failing is most likely) must never
/// relax him, so a last good fraction ≥ 0.85 is held; below that, unknown.
public func reportedFraction(reading: Double?, lastGood: Double?) -> Double? {
    if let reading { return reading }
    guard let lastGood, lastGood >= holdFractionAtOrAbove else { return nil }
    return lastGood
}
