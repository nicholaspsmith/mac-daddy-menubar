// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import os
import StatusItemKit

private let log = Logger(subsystem: "com.nicholaspsmith.MacDaddy", category: "uaWatchdog")

/// Kills runaway Universal Audio processes and brings Apollo audio back by
/// kickstarting the mixer engine. Was the `ua-watchdog` launchd agent; only
/// runs while Mac Daddy does, and only on a Mac with UA software installed.
final class UAWatchdogDuty: NSObject, Duty {
    var onSweep: ((Flourish) -> Void)?
    var onChange: (() -> Void)?

    static let agentLabel = "com.nicholassmith.ua-watchdog"
    private static let engineLabel = "com.uaudio.ua_mixer_engine"
    private static let uaFolder = "/Library/Application Support/Universal Audio"

    private let defaults = UserDefaults.standard
    private let notifier: Notifier
    private let sampleSeconds: TimeInterval = 60
    private var watchdog = UAWatchdog()
    private let queue = DispatchQueue(label: "macdaddy.uawatchdog")
    private var inFlight = false
    private var generation = 0
    private var lastSample = Date.distantPast
    private var lastError: String?
    private let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/state/ua-watchdog.log")

    init(notifier: Notifier) { self.notifier = notifier }

    var enabled: Bool {
        get { defaults.object(forKey: "uaWatchdog.enabled") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "uaWatchdog.enabled")
            // Off and on again starts counting from nothing.
            watchdog.reset()
            generation += 1
            lastError = nil
            onChange?()
        }
    }

    /// UA software is installed; without it the duty neither runs nor shows.
    var isApplicable: Bool { FileManager.default.fileExists(atPath: Self.uaFolder) }

    /// Enabled and with something to watch: what keeps Mac Daddy awake.
    var isActive: Bool { enabled && isApplicable }

    func tick(now: Date) {
        guard enabled, !inFlight, now.timeIntervalSince(lastSample) >= sampleSeconds - 0.5, isApplicable else { return }
        lastSample = now
        inFlight = true
        let gen = generation
        queue.async { [weak self] in
            let ps = Shell.run("/bin/ps", ["-Ao", "pid=,ppid=,pcpu=,command=", "-ww"])
            DispatchQueue.main.async { self?.apply(ps: ps, generation: gen) }
        }
    }

    private func apply(ps: String?, generation gen: Int) {
        inFlight = false
        guard enabled, gen == generation else { return }
        guard let ps else { lastError = "Couldn't list processes"; return }
        lastError = nil
        let scan = watchdog.scan(ps: ps)
        for k in scan.kills {
            // As the script did: the KILLED line is written whatever kill(2) says.
            if kill(pid_t(k.pid), SIGKILL) != 0 { log.error("kill \(k.pid) failed: errno \(errno)") }
            log.notice("killed runaway \(k.label, privacy: .public) [\(k.pid)]")
        }
        let now = Date()
        append(scan.messages.map { UAWatchdogLog.line($0, at: now) }.joined())
        guard let body = scan.notification else { return }
        if scan.audioPathHit {
            let target = "gui/\(getuid())/\(Self.engineLabel)"
            queue.async { [weak self] in
                _ = Shell.run("/bin/launchctl", ["kickstart", "-k", target])
                DispatchQueue.main.async { self?.append(UAWatchdogLog.line(UAWatchdog.kickstartMessage, at: Date())) }
            }
        }
        notifier.post(title: "UA Watchdog", body: body)
        onSweep?(.hatTip)
    }

    private func append(_ text: String) {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return }
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: logURL) }
    }

    func addMenuItems(to menu: NSMenu) {
        guard isApplicable else { return }
        heading("UA Watchdog", error: lastError).forEach(menu.addItem)
        let toggle = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self; toggle.state = enabled ? .on : .off
        menu.addItem(indented(toggle))
        let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        for line in UAWatchdogLog.summary(text, now: Date()) {
            let i = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(indented(i))
        }
        if FileManager.default.fileExists(atPath: logURL.path) {
            let open = NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "")
            open.target = self
            menu.addItem(indented(open))
        }
    }

    @objc private func toggleEnabled() { enabled.toggle() }
    @objc private func openLog() { NSWorkspace.shared.open(logURL) }
}
