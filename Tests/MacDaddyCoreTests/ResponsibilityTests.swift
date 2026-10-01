// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MacDaddyCore

final class ResponsibilityTests: XCTestCase {
    func testMissingSymbolGivesNoLookup() {
        var asked: [String] = []
        XCTAssertNil(Responsibility.resolve { asked.append($0); return nil })
        XCTAssertEqual(asked, ["responsibility_get_pid_responsible_for_pid"])
    }

    func testRealSymbolResolvesAtRuntime() {
        let lookup = Responsibility.resolve(Responsibility.dlsymDefault)
        XCTAssertNotNil(lookup)
        XCTAssertGreaterThan(lookup?(Int(getpid())) ?? 0, 0)
    }

    func testWithoutTheLookupPathRulesStillApply() {
        // No responsible PID (lookup unavailable): XPC still excluded, a plain orphan still counts.
        let s = LostSouls(window: 60, sampleInterval: 30)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let paths = [1: "/x/Thing.xpc/Contents/MacOS/Thing", 2: "/opt/tools/runaway"]
        for at in [0, 30, 60] {
            s.record(snapshot: "  101 1 99 01:00:\(String(format: "%02d", at % 60)) a\n  102 1 99 01:00:\(String(format: "%02d", at % 60)) b",
                     at: t0.addingTimeInterval(Double(at)),
                     detail: { LostSouls.ProcDetail(path: paths[$0 - 100], start: t0, responsiblePID: nil, responsiblePath: nil) })
        }
        XCTAssertEqual(s.qualifying(now: t0.addingTimeInterval(60), allowlist: [], launchdJobs: [:], isApp: { _ in false }).map(\.pid), [102])
    }
}
