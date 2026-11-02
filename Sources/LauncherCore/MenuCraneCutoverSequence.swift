// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// The order of the cut-over from a running Menu Crane, with the system
/// calls injected (Mac Daddy's `MenuCraneCutover` supplies the real ones):
///
/// 1. If Menu Crane is running, ask it to quit; poll for `quitTimeout`, then
///    force it. Until it has gone it holds ⌘Space.
/// 2. If its bundle is installed, run `<bundle> --login off`, so it doesn't
///    come back at login. Waits at most `loginOffTimeout` for the answer.
/// 3. Migrate its settings and files (the snapshot is final now it has quit).
/// 4. `completion`, exactly once.
///
/// Every step is logged under the `launcher` category.
public final class MenuCraneCutoverSequence {
    public struct Steps {
        public var isRunning: () -> Bool
        public var terminate: () -> Void
        public var forceTerminate: () -> Void
        public var bundleURL: () -> URL?
        /// Runs the bundle's `--login off`; calls back with the exit status,
        /// or nil when it couldn't be started. Called back on the main queue.
        public var loginOff: (URL, @escaping (Int32?) -> Void) -> Void
        public var migrate: () -> Void

        public init(isRunning: @escaping () -> Bool, terminate: @escaping () -> Void,
                    forceTerminate: @escaping () -> Void, bundleURL: @escaping () -> URL?,
                    loginOff: @escaping (URL, @escaping (Int32?) -> Void) -> Void,
                    migrate: @escaping () -> Void) {
            self.isRunning = isRunning
            self.terminate = terminate
            self.forceTerminate = forceTerminate
            self.bundleURL = bundleURL
            self.loginOff = loginOff
            self.migrate = migrate
        }
    }

    public static let quitTimeout: TimeInterval = 5
    public static let pollInterval: TimeInterval = 0.1
    /// After a force quit, how long to wait for the process to go.
    public static let forceGrace: TimeInterval = 1
    public static let loginOffTimeout: TimeInterval = 5

    private let steps: Steps
    private let after: (TimeInterval, @escaping () -> Void) -> Void

    /// - Parameter after: runs a closure after a delay, on the main queue.
    public init(steps: Steps,
                after: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, run in
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: run)
                }) {
        self.steps = steps
        self.after = after
    }

    public func run(completion: @escaping () -> Void) {
        quit { [self] in
            loginOff { [self] in
                steps.migrate()
                coreLog.info("cut-over done")
                completion()
            }
        }
    }

    // MARK: - Steps

    private func quit(then next: @escaping () -> Void) {
        guard steps.isRunning() else { next(); return }
        coreLog.info("Menu Crane is running: asking it to quit")
        steps.terminate()
        let polls = Int((Self.quitTimeout / Self.pollInterval).rounded())
        let graces = Int((Self.forceGrace / Self.pollInterval).rounded())
        waitForQuit(pollsLeft: polls, forced: false, graces: graces, then: next)
    }

    private func waitForQuit(pollsLeft: Int, forced: Bool, graces: Int, then next: @escaping () -> Void) {
        if !steps.isRunning() {
            coreLog.info("Menu Crane quit\(forced ? " (forced)" : "", privacy: .public)")
            next()
            return
        }
        if pollsLeft <= 0 {
            guard !forced else {
                coreLog.error("Menu Crane still running after a force quit; going on")
                next()
                return
            }
            coreLog.notice("Menu Crane didn't quit in \(Self.quitTimeout)s: forcing it")
            steps.forceTerminate()
            waitForQuit(pollsLeft: graces, forced: true, graces: graces, then: next)
            return
        }
        after(Self.pollInterval) { [self] in
            waitForQuit(pollsLeft: pollsLeft - 1, forced: forced, graces: graces, then: next)
        }
    }

    private func loginOff(then next: @escaping () -> Void) {
        guard let url = steps.bundleURL() else {
            coreLog.info("no Menu Crane bundle installed")
            next()
            return
        }
        var finished = false
        let finish: (String) -> Void = { outcome in
            guard !finished else { return }
            finished = true
            coreLog.info("Menu Crane --login off: \(outcome, privacy: .public)")
            next()
        }
        coreLog.info("turning Menu Crane's login item off (\(url.path, privacy: .public))")
        steps.loginOff(url) { status in
            finish(status.map { "exit \($0)" } ?? "couldn't run")
        }
        after(Self.loginOffTimeout) { finish("no answer in \(Self.loginOffTimeout)s") }
    }
}
