// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// The old `ua-watchdog.sh` agent, as built-in Hoes rules:
///   * an orphaned UA Mixer Helper (PPID 1) at 80 % or more is killed on sight —
///     the bug that silently takes Apollo audio down;
///   * the real-time UA Mixer Engine at 98 % for 2 minutes;
///   * any other UA process at 90 % for 1 minute.
/// All SIGKILL; when the helper or the engine dies, the mixer engine is
/// kickstarted so sound comes back.
public enum UAWatchdog {
    /// Present only when UA software is installed; the built-ins need it.
    public static let folder = "/Library/Application Support/Universal Audio"
    public static let engineLabel = "com.uaudio.ua_mixer_engine"
    /// Logged to ua-watchdog.log after the mixer engine is kickstarted.
    public static let kickstartMessage = "kickstarted UA mixer engine to restore audio path"

    private static let marks = ["/Universal Audio/", "UA Connect.app", "UA Mixer"]
    private static let audioPath = ["UA Mixer Helper.app", "UA Mixer Engine.app"]

    public static let builtInRules: [HoeRule] = [
        HoeRule(id: "ua.helper", name: "Orphaned UA Mixer Helper",
                match: .command(any: ["UA Mixer Helper.app"], none: [], orphanedOnly: true),
                threshold: 80, minutes: 0, action: .kill, restartLabel: engineLabel, restartAfterKill: true,
                builtIn: true, requiresPath: folder),
        HoeRule(id: "ua.engine", name: "UA Mixer Engine",
                match: .command(any: ["UA Mixer Engine.app"], none: [], orphanedOnly: false),
                threshold: 98, minutes: 2, action: .kill, restartLabel: engineLabel, restartAfterKill: true,
                builtIn: true, requiresPath: folder),
        HoeRule(id: "ua.other", name: "Other UA processes",
                match: .command(any: marks, none: ["UA Mixer Engine.app"], orphanedOnly: false),
                threshold: 90, minutes: 1, action: .kill, restartLabel: engineLabel, restartAfterKill: true,
                restartOnlyIf: audioPath, builtIn: true, requiresPath: folder),
    ]

    public static func isUA(_ command: String) -> Bool { marks.contains { command.contains($0) } }

    /// A readable name for a UA process.
    public static func label(_ command: String) -> String {
        if command.contains("UA Mixer Helper.app") { return "UA Mixer Helper" }
        if command.contains("UA Mixer Engine.app") { return "UA Mixer Engine" }
        if command.contains("UA Connect.app") { return "UA Connect" }
        if command.contains("UAD Meter") { return "UAD Meter" }
        if command.contains("UAD Console.app") { return "UAD Console" }
        // zsh's `:t`: everything after the last slash of the whole command line.
        return command.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? command
    }

    /// The old agent's KILLED line, so ua-watchdog.log's history carries on.
    public static func killMessage(_ d: Hoes.Due, rule: HoeRule) -> String {
        if case .command(_, _, true) = rule.match {
            return "KILLED orphaned \(d.name) pid=\(d.pid) cpu=\(d.cpu)% (fast-path: PPID=1)"
        }
        return "KILLED runaway \(d.name) pid=\(d.pid) cpu=\(d.cpu)% (>=\(rule.threshold)% x \(d.samples) ticks)"
    }

    public static func notification(label: String, audioRestored: Bool) -> String {
        "Pimp slapped runaway \(label)" + (audioRestored ? " — audio restored" : "")
    }

    /// Whether `launchctl print-disabled gui/<uid>` lists `label` as disabled
    /// (`=> disabled`, or `=> true` on older macOS).
    public static func isDisabled(_ label: String, printDisabled text: String) -> Bool {
        text.split(separator: "\n").contains { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t == "\"\(label)\" => disabled" || t == "\"\(label)\" => true"
        }
    }
}
