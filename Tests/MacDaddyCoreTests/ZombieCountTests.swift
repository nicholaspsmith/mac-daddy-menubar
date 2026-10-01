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
        let r = ZombieCount.parse(ps, user: "someone", excludingPID: 99)
        XCTAssertEqual(r.count, 7)
        XCTAssertEqual(r.quittable, ZombieParent(pid: 500, comm: "Leaky Helper", zombies: 2))
    }

    func testNoZombies() {
        XCTAssertEqual(ZombieCount.parse("  10 1 someone S zsh\n", user: "someone", excludingPID: 99),
                       ZombieReport(count: 0, quittable: nil))
    }

    func testMalformedLinesIgnored() {
        XCTAssertEqual(ZombieCount.parse("\ngarbage\n  x y z Z w\n", user: "someone", excludingPID: 99).count, 0)
    }

    func testSystemParentIsNeverOfferedEvenWithTheMostZombies() {
        let ps = """
          300     1 someone  Ss   /System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow
          301   300 someone  Z    <defunct>
          302   300 someone  Z    <defunct>
          303   300 someone  Z    <defunct>
          400     1 someone  S    /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock
          401   400 someone  Z    <defunct>
          402   400 someone  Z    <defunct>
          500     1 someone  S    /Applications/Leaky.app/Contents/MacOS/Leaky Helper
          501   500 someone  Z    <defunct>
        """
        let r = ZombieCount.parse(ps, user: "someone", excludingPID: 99)
        XCTAssertEqual(r.count, 6)
        XCTAssertEqual(r.quittable?.pid, 500)
        XCTAssertEqual(r.quittable?.zombies, 1)
    }

    func testEverySystemNameIsProtected() {
        for name in ["loginwindow", "WindowServer", "Dock", "Finder", "SystemUIServer", "ControlCenter", "launchd"] {
            let ps = "  300 1 someone S /some/path/\(name)\n  301 300 someone Z <defunct>\n"
            XCTAssertNil(ZombieCount.parse(ps, user: "someone", excludingPID: 99).quittable, name)
        }
    }

    func testOwnPIDIsNeverOffered() {
        let ps = """
           99     1 someone  S    /Applications/Mac Daddy.app/Contents/MacOS/MacDaddy
          100    99 someone  Z    <defunct>
          101    99 someone  Z    <defunct>
          500     1 someone  S    Leaky Helper
          501   500 someone  Z    <defunct>
        """
        XCTAssertEqual(ZombieCount.parse(ps, user: "someone", excludingPID: 99).quittable,
                       ZombieParent(pid: 500, comm: "Leaky Helper", zombies: 1))
    }

    func testStillSameProcessComparesBasenames() {
        let comm = "/Applications/Leaky.app/Contents/MacOS/Leaky Helper"
        XCTAssertTrue(ZombieCount.stillSameProcess(expectedComm: comm, currentPath: comm))
        XCTAssertTrue(ZombieCount.stillSameProcess(expectedComm: "Leaky Helper", currentPath: comm))
        XCTAssertFalse(ZombieCount.stillSameProcess(expectedComm: comm, currentPath: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"))
        XCTAssertFalse(ZombieCount.stillSameProcess(expectedComm: comm, currentPath: nil))
        XCTAssertFalse(ZombieCount.stillSameProcess(expectedComm: comm, currentPath: ""))
    }

    func testStillSameProcessRefusesAProtectedProcess() {
        let lw = "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"
        XCTAssertFalse(ZombieCount.stillSameProcess(expectedComm: lw, currentPath: lw))
    }
}
