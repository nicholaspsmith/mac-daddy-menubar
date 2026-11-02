// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// What clicking a crashing-out (crash-looping) process does. Ending the
/// process itself is pointless: whatever restarts it starts another within
/// seconds. The fix is to stop the thing that restarts it.
public enum CrashFix: Equatable {
    /// One of your launchd agents (gui domain) restarts it: unload the agent
    /// with `launchctl bootout`, which holds until you log in again or its
    /// app loads it again.
    case bootout(label: String)
    /// An iOS Simulator's own launchd (`launchd_sim`) restarts it: shut the
    /// simulators down (`xcrun simctl shutdown all`).
    case shutDownSimulators
    /// A process of yours keeps starting it (a script or app in a loop):
    /// quit that process.
    case quitParent(pid: Int, comm: String)
    /// Nothing Mac Daddy may stop: a macOS system service, or someone else's.
    case none(reason: String)

    /// `parent` is the restarting PID and `parentRec` its row (nil once
    /// gone); `agentLabel` the gui-domain launchd label running the looping
    /// process, if any; `user` you; `myPID` Mac Daddy.
    public static func plan(parent: Int, parentRec: ProcRec?, agentLabel: String?, user: String, myPID: Int) -> CrashFix {
        if parent <= 1 {
            if let agentLabel { return .bootout(label: agentLabel) }
            return .none(reason: "macOS itself restarts it as a system service, which only an administrator can stop.")
        }
        guard let parentRec else { return .none(reason: "Whatever was restarting it has already exited.") }
        let name = displayName(parentRec.comm)
        if name == "launchd_sim" { return .shutDownSimulators }
        guard parentRec.user == user else { return .none(reason: "\(name), which restarts it, belongs to \(parentRec.user), not you.") }
        guard parent != myPID else { return .none(reason: "Mac Daddy itself is starting it.") }
        guard !ZombieCount.isProtected(comm: parentRec.comm) else {
            return .none(reason: "\(name) restarts it, and quitting \(name) would break your desktop.")
        }
        return .quitParent(pid: parent, comm: parentRec.comm)
    }
}

/// `launchctl print gui/<uid>`'s services block: "pid status label" rows.
public enum LaunchctlServices {
    /// Running PID → label. Rows with PID 0 or "-" (not running) are skipped.
    public static func parse(_ text: String) -> [Int: String] {
        var result: [Int: String] = [:]
        var inServices = false
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "services = {" { inServices = true; continue }
            guard inServices else { continue }
            if line == "}" { break }
            let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard f.count >= 3, let pid = Int(f[0]), pid > 0 else { continue }
            result[pid] = String(f[2])
        }
        return result
    }
}
