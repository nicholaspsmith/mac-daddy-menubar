// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import LauncherCore

/// Takes over from a Menu Crane that is still running when Mac Daddy starts
/// (parity installs Mac Daddy 1.17.0 while Menu Crane runs): quits it, turns
/// its login item off, then brings its settings and files over once. Runs on
/// every launch, before the launcher starts (Menu Crane holds ⌘Space until it
/// has gone); with no Menu Crane installed it only checks the one-time
/// migration flag. `LauncherCore.MenuCraneCutoverSequence` holds the order;
/// this supplies the system calls.
final class MenuCraneCutover {
    static let bundleID = MenuCraneMigration.oldDomain
    private var sequence: MenuCraneCutoverSequence?

    func run(completion: @escaping () -> Void) {
        let steps = MenuCraneCutoverSequence.Steps(
            isRunning: { !Self.runningApps().isEmpty },
            terminate: { Self.runningApps().forEach { $0.terminate() } },
            forceTerminate: { Self.runningApps().forEach { $0.forceTerminate() } },
            bundleURL: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) },
            loginOff: Self.loginOff,
            migrate: Self.migrate
        )
        let sequence = MenuCraneCutoverSequence(steps: steps)
        self.sequence = sequence
        sequence.run { [weak self] in
            self?.sequence = nil
            completion()
        }
    }

    private static func runningApps() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { !$0.isTerminated }
    }

    /// `<bundle>/Contents/MacOS/<CFBundleExecutable> --login off`: StatusItemKit's
    /// LoginCLI, which unregisters Menu Crane's own SMAppService and exits headless.
    private static func loginOff(_ bundleURL: URL, done: @escaping (Int32?) -> Void) {
        guard let executable = Bundle(url: bundleURL)?.executableURL else {
            launcherLog.error("no executable in \(bundleURL.path, privacy: .public)")
            done(nil)
            return
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--login", "off"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            DispatchQueue.main.async { done(status) }
        }
        do {
            try process.run()
        } catch {
            launcherLog.error("couldn't run \(executable.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            done(nil)
        }
    }

    /// The one-time copy of Menu Crane's settings and files into Mac Daddy's.
    private static func migrate() {
        guard let domain = Bundle.main.bundleIdentifier else {
            launcherLog.error("no bundle identifier (unbundled run): Menu Crane settings not migrated")
            return
        }
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        let old = MenuCraneMigration.readDomain(MenuCraneMigration.oldDomain)
        guard let written = MenuCraneMigration.applyOnce(old: old, installed: installed, to: .standard, domain: domain) else { return }
        let files = MenuCraneMigration.copyFiles(from: MenuCraneMigration.oldSupportDirectory, to: AppSupport.directory)
        launcherLog.notice("migrated from Menu Crane: \((written + files).joined(separator: ", "), privacy: .public)")
    }
}
