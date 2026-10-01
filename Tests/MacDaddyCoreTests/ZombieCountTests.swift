// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MacDaddyCore

final class ZombieCountTests: XCTestCase {
    func testCountsAndPicksTheWorstOwnParent() {
        let ps = """
            1     0 root     Ss   launchd
          500     1 someone  S    Leaky Helper
          501   500 someone  Z    <defunct>
          502   500 someone  Z    <defunct>
          600     1 someone  S    Other
          601   600 someone  Z    <defunct>
          700     1 root     S    rootd
          701   700 root     Z    <defunct>
          702   700 root     Z    <defunct>
          703   700 root     Z    <defunct>
          800     1 someone  Z    <defunct>
        """
        let r = ZombieCount.parse(ps, user: "someone")
        XCTAssertEqual(r.count, 7)
        XCTAssertEqual(r.quittable, ZombieParent(pid: 500, comm: "Leaky Helper", zombies: 2))
    }

    func testNoZombies() {
        XCTAssertEqual(ZombieCount.parse("  10 1 someone S zsh\n", user: "someone"),
                       ZombieReport(count: 0, quittable: nil))
    }

    func testMalformedLinesIgnored() {
        XCTAssertEqual(ZombieCount.parse("\ngarbage\n  x y z Z w\n", user: "someone").count, 0)
    }
}
