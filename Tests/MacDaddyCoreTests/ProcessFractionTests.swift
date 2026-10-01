// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MacDaddyCore

final class ProcessFractionTests: XCTestCase {
    func testFraction() {
        XCTAssertEqual(processFraction(count: 1333, limit: 2666), 0.5)
        XCTAssertNil(processFraction(count: nil, limit: 2666))
        XCTAssertNil(processFraction(count: 10, limit: 0))
    }

    func testFreshReadingAlwaysWins() {
        XCTAssertEqual(reportedFraction(reading: 0.3, lastGood: 0.95), 0.3)
        XCTAssertEqual(reportedFraction(reading: 0.9, lastGood: nil), 0.9)
    }

    func testFailedReadAtTheLimitKeepsTheLastGoodFraction() {
        XCTAssertEqual(reportedFraction(reading: nil, lastGood: 0.85), 0.85)
        XCTAssertEqual(reportedFraction(reading: nil, lastGood: 0.99), 0.99)
    }

    func testFailedReadBelowTheLimitIsUnknown() {
        XCTAssertNil(reportedFraction(reading: nil, lastGood: 0.84))
        XCTAssertNil(reportedFraction(reading: nil, lastGood: nil))
    }
}
