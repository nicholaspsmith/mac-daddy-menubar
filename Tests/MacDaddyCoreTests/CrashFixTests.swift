// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MacDaddyCore

final class CrashFixTests: XCTestCase {
    private func p(_ pid: Int, _ comm: String, user: String = "nick") -> ProcRec {
        ProcRec(pid: pid, ppid: 1, user: user, etime: "", comm: comm)
    }
    private func plan(_ parent: Int, _ rec: ProcRec?, label: String? = nil) -> CrashFix {
        CrashFix.plan(parent: parent, parentRec: rec, agentLabel: label, user: "nick", myPID: 500)
    }

    func testYourLaunchdAgentIsBootedOut() {
        XCTAssertEqual(plan(1, nil, label: "com.example.helper"), .bootout(label: "com.example.helper"))
    }
    func testASystemServiceCannotBeStopped() {
        guard case .none = plan(1, nil) else { return XCTFail() }
    }
    func testASimulatorIsShutDown() {
        XCTAssertEqual(plan(42, p(42, "/Library/Developer/CoreSimulator/launchd_sim")), .shutDownSimulators)
    }
    func testYourLoopingScriptIsQuit() {
        XCTAssertEqual(plan(42, p(42, "/bin/bash")), .quitParent(pid: 42, comm: "/bin/bash"))
    }
    func testNeverSomeoneElsesNeverMacDaddyNeverTheDesktop() {
        guard case .none = plan(42, p(42, "/bin/bash", user: "root")) else { return XCTFail() }
        guard case .none = plan(500, p(500, "MacDaddy")) else { return XCTFail() }
        guard case .none = plan(42, p(42, "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock")) else { return XCTFail() }
        guard case .none = plan(42, nil) else { return XCTFail() }
    }
    func testParsesLaunchctlServices() {
        let text = """
        gui/501 = {
        \tservices = {
        \t\t    1015      - \tcom.apple.syncdefaultsd
        \t\t       0      0 \tcom.apple.DataDetectorsLocalSources
        \t\t       -     -9 \tcom.example.crasher
        \t}
        \tendpoints = {
        \t\t    9999      - \tnot.a.service
        \t}
        }
        """
        XCTAssertEqual(LaunchctlServices.parse(text), [1015: "com.apple.syncdefaultsd"])
    }
}
