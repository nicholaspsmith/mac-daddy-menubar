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
}
