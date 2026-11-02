// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import LauncherCore

/// A clock the test advances by hand: `after` only queues, `drain` runs.
private final class FakeClock {
    private(set) var now: TimeInterval = 0
    private var queue: [(at: TimeInterval, seq: Int, run: () -> Void)] = []
    private var seq = 0

    func after(_ delay: TimeInterval, _ run: @escaping () -> Void) {
        seq += 1
        queue.append((now + delay, seq, run))
    }

    func drain(limit: Int = 10_000) {
        var steps = 0
        while !queue.isEmpty, steps < limit {
            queue.sort { ($0.at, $0.seq) < ($1.at, $1.seq) }
            let next = queue.removeFirst()
            now = max(now, next.at)
            next.run()
            steps += 1
        }
    }
}

final class MenuCraneCutoverTests: XCTestCase {
    private var events: [String] = []
    private var running = false
    private var bundle: URL? = URL(fileURLWithPath: "/Applications/Menu Crane.app")
    /// Polls left until a terminated app reports it has gone; nil = never.
    private var quitsAfterPolls: Int? = 3
    private var loginOffAnswers = true
    private let clock = FakeClock()
    /// The fake clock's time when `completion` ran.
    private var doneAt: TimeInterval?

    private func sequence() -> MenuCraneCutoverSequence {
        var pollsLeft = 0
        var terminated = false
        let steps = MenuCraneCutoverSequence.Steps(
            isRunning: { [unowned self] in
                guard self.running else { return false }
                if terminated, let limit = self.quitsAfterPolls {
                    pollsLeft += 1
                    if pollsLeft > limit { self.running = false }
                }
                return self.running
            },
            terminate: { [unowned self] in self.events.append("terminate"); terminated = true },
            forceTerminate: { [unowned self] in self.events.append("force"); self.running = false },
            bundleURL: { [unowned self] in self.bundle },
            loginOff: { [unowned self] url, done in
                self.events.append("loginOff \(url.lastPathComponent)")
                if self.loginOffAnswers { done(0) }
            },
            migrate: { [unowned self] in self.events.append("migrate") }
        )
        return MenuCraneCutoverSequence(steps: steps, after: clock.after)
    }

    private func runToEnd() {
        sequence().run { [unowned self] in self.events.append("done"); self.doneAt = self.clock.now }
        clock.drain()
    }

    func testQuitsRunningAppThenLoginOffThenMigrates() throws {
        running = true
        runToEnd()
        XCTAssertEqual(events, ["terminate", "loginOff Menu Crane.app", "migrate", "done"])
        XCTAssertLessThan(try XCTUnwrap(doneAt), MenuCraneCutoverSequence.quitTimeout)
    }

    func testForceQuitsAfterFiveSeconds() throws {
        running = true
        quitsAfterPolls = nil
        runToEnd()
        XCTAssertEqual(events, ["terminate", "force", "loginOff Menu Crane.app", "migrate", "done"])
        XCTAssertEqual(try XCTUnwrap(doneAt), MenuCraneCutoverSequence.quitTimeout, accuracy: 0.01)
    }

    func testNotRunningSkipsTheQuit() {
        runToEnd()
        XCTAssertEqual(events, ["loginOff Menu Crane.app", "migrate", "done"])
    }

    func testNoBundleRunsNoLoginOff() {
        bundle = nil
        runToEnd()
        XCTAssertEqual(events, ["migrate", "done"])
    }

    func testLoginOffThatNeverAnswersStillCompletesOnce() throws {
        loginOffAnswers = false
        runToEnd()
        XCTAssertEqual(events, ["loginOff Menu Crane.app", "migrate", "done"])
        XCTAssertEqual(try XCTUnwrap(doneAt), MenuCraneCutoverSequence.loginOffTimeout, accuracy: 0.01)
    }

    func testLateLoginOffAnswerDoesNotCompleteTwice() {
        var late: ((Int32?) -> Void)?
        let steps = MenuCraneCutoverSequence.Steps(
            isRunning: { false }, terminate: {}, forceTerminate: {},
            bundleURL: { URL(fileURLWithPath: "/x.app") },
            loginOff: { _, done in late = done },
            migrate: { [unowned self] in self.events.append("migrate") }
        )
        MenuCraneCutoverSequence(steps: steps, after: clock.after).run { [unowned self] in self.events.append("done") }
        clock.drain()
        late?(0)
        XCTAssertEqual(events, ["migrate", "done"])
    }
}
