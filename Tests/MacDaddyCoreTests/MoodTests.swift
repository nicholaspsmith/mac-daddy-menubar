// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MacDaddyCore

final class MoodTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func level(_ f: Double?) -> MoodLevel {
        Mood.compute(fraction: f, anyCleanupEnabled: true, lastFlourish: nil, now: t0).level
    }

    func testThresholds() {
        XCTAssertEqual(level(0), .cool)
        XCTAssertEqual(level(0.5999), .cool)
        XCTAssertEqual(level(0.60), .sweating)
        XCTAssertEqual(level(0.8499), .sweating)
        XCTAssertEqual(level(0.85), .redHot)
        XCTAssertEqual(level(1.3), .redHot)
    }

    func testUnreadableCountIsCool() {
        XCTAssertEqual(level(nil), .cool)
    }

    func testAsleepKeepsTheLevel() {
        let m = Mood.compute(fraction: 0.9, anyCleanupEnabled: false, lastFlourish: nil, now: t0)
        XCTAssertTrue(m.asleep)
        XCTAssertEqual(m.level, .redHot)
    }

    func testFlourishExpiresAtTwoSeconds() {
        let at = { (dt: Double) in
            Mood.compute(fraction: 0.1, anyCleanupEnabled: true,
                         lastFlourish: (.hatTip, self.t0), now: self.t0.addingTimeInterval(dt)).flourish
        }
        XCTAssertEqual(at(0), .hatTip)
        XCTAssertEqual(at(1.99), .hatTip)
        XCTAssertNil(at(2.0))
        XCTAssertNil(at(-1))   // a flourish from the future (clock change) is ignored
    }
}
