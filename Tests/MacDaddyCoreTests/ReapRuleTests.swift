// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MacDaddyCore

final class ReapRuleTests: XCTestCase {
    func testElapsedParsesEveryPsForm() {
        XCTAssertEqual(ReapRule.elapsedSeconds("00:59"), 59)
        XCTAssertEqual(ReapRule.elapsedSeconds("15:00"), 900)
        XCTAssertEqual(ReapRule.elapsedSeconds("01:02:03"), 3723)
        XCTAssertEqual(ReapRule.elapsedSeconds("2-00:00:01"), 172_801)
        XCTAssertNil(ReapRule.elapsedSeconds(""))
        XCTAssertNil(ReapRule.elapsedSeconds("ab:cd"))
    }

    func testReapsOnlyHeadlessGodotPastTheThreshold() {
        let ps = """
          101   20:00 /Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/someone/game -s test.gd
          102   05:00 /Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/someone/game
          103 1-00:00:00 /Applications/Godot.app/Contents/MacOS/Godot -e --path /Users/someone/game
          104   30:00 /usr/bin/python3 fake --headless MacOS/Godot
        """
        XCTAssertEqual(ReapRule.pidsToReap(psOutput: ps, thresholdSeconds: 900), [101])
    }

    func testMalformedLinesNeverReap() {
        let ps = "\n  PID ELAPSED COMMAND\nnot-a-pid 99:99 MacOS/Godot --headless\n  7\n"
        XCTAssertEqual(ReapRule.pidsToReap(psOutput: ps, thresholdSeconds: 0), [])
    }

    func testReapsGodotInAPathWithSpaces() {
        let ps = "  201   20:00 /Applications/Godot Engine.app/Contents/MacOS/Godot --headless --path /Users/someone/game"
        XCTAssertEqual(ReapRule.pidsToReap(psOutput: ps, thresholdSeconds: 900), [201])
    }

    func testThresholdBoundary() {
        let ps = """
          301   15:00 /Applications/Godot.app/Contents/MacOS/Godot --headless
          302   14:59 /Applications/Godot.app/Contents/MacOS/Godot --headless
        """
        XCTAssertEqual(ReapRule.pidsToReap(psOutput: ps, thresholdSeconds: 900), [301])
    }
}
