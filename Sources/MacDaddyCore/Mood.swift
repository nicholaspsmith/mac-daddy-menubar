// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// The short celebration after a duty did something.
public enum Flourish: Equatable { case hatTip, chainGlint }

/// How hot the process count is running.
public enum MoodLevel: Equatable { case cool, sweating, redHot }

/// Everything the icon needs to draw Mac Daddy.
public struct Mood: Equatable {
    public let level: MoodLevel
    public let asleep: Bool
    public let flourish: Flourish?

    public static let flourishDuration: TimeInterval = 2.0

    /// `fraction` is processes / per-user limit; nil when it could not be read,
    /// which must never make him sweat.
    public static func compute(fraction: Double?, anyCleanupEnabled: Bool,
                               lastFlourish: (Flourish, Date)?, now: Date) -> Mood {
        let level: MoodLevel
        switch fraction {
        case let f? where f >= 0.85: level = .redHot
        case let f? where f >= 0.60: level = .sweating
        default: level = .cool
        }
        var flourish: Flourish?
        if let (kind, at) = lastFlourish {
            let age = now.timeIntervalSince(at)
            if age >= 0 && age < flourishDuration { flourish = kind }
        }
        return Mood(level: level, asleep: !anyCleanupEnabled, flourish: flourish)
    }
}
