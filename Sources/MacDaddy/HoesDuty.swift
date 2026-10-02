// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import os
import Security
import StatusItemKit

private let log = Logger(subsystem: "com.nicholaspsmith.MacDaddy", category: "hoes")

/// What `ps` can't say about a process, cached by executable path. Used only
/// on the duty's queue.
private final class ProcessFacts {
    private var apple: [String: Bool] = [:]
    private var bundleIDs: [String: String?] = [:]
    private let requirement: SecRequirement? = {
        var r: SecRequirement?
        return SecRequirementCreateWithString("anchor apple" as CFString, [], &r) == errSecSuccess ? r : nil
    }()

    /// Signed by Apple as part of macOS (`anchor apple`). Unsigned, ad-hoc and
    /// Developer ID code is third-party.
    func isApple(_ path: String) -> Bool {
        if let v = apple[path] { return v }
        var code: SecStaticCode?
        var v = false
        if let requirement, SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
           let code {
            v = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSDoNotValidateResources), requirement) == errSecSuccess
        }
        apple[path] = v
        return v
    }

    /// The innermost app bundle's identifier, for an executable inside one.
    func bundleID(_ path: String) -> String? {
        if let v = bundleIDs[path] { return v }
        let v = path.range(of: ".app/", options: .backwards).flatMap { Bundle(path: String(path[..<$0.upperBound]))?.bundleIdentifier }
        bundleIDs[path] = v
        return v
    }

    func detail(_ pid: Int, launchdJobs: [Int: String]) -> Hoes.Detail? {
        let p = pid_t(pid)
        guard let path = executablePath(of: p), let info = bsdInfo(p) else { return nil }
        return Hoes.Detail(path: path, start: startDate(info), bundleID: bundleID(path),
                           thirdParty: !isApple(path), launchdLabel: launchdJobs[pid])
    }
}

/// Learns which third-party processes you force-quit while they pin the CPU
/// and offers to end them for you next time. The UA watchdog's rules are built in.
final class HoesDuty: NSObject, Duty {
    var onSweep: ((Flourish) -> Void)?
    var onChange: (() -> Void)?

    private static let forceQuitApps: Set<String> = ["com.apple.ActivityMonitor", "com.apple.loginwindow"]
    private static let uaRuleIDs = Set(UAWatchdog.builtInRules.map(\.id))

    private let defaults = UserDefaults.standard
    private let notifier: Notifier
    private let sampleSeconds: TimeInterval = 30
    private let menuLimit = 8
    private var hoes = Hoes()
    private var state: HoesState
    private let facts = ProcessFacts()
    private let queue = DispatchQueue(label: "macdaddy.hoes")
    private var inFlight = false
    private var generation = 0
    private var lastSample = Date.distantPast
    private var lastError: String?
    /// When Activity Monitor or the Force Quit window was last in front.
    private var forceQuitWindowAt: Date?
    private(set) var current: [Hoes.Hoe] = []
    private let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MacDaddy/hoes.log")
    private let uaLogURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state/ua-watchdog.log")

    init(notifier: Notifier) {
        self.notifier = notifier
        state = HoesState.load(from: defaults)
        super.init()
        // The UA watchdog's own switch, if it was ever turned off, carries over.
        state.ensureBuiltIns(UAWatchdog.builtInRules, paused: defaults.object(forKey: "uaWatchdog.enabled") as? Bool == false)
        save()
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(appSwitched(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appSwitched(_:)), name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
    }

    var enabled: Bool {
        get { defaults.object(forKey: "hoes.enabled") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "hoes.enabled")
            // Off and on again starts from nothing.
            hoes = Hoes(sampleInterval: sampleSeconds)
            generation += 1
            current = []; lastError = nil
            onChange?()
        }
    }

    /// The retired agent had been switched off: so are its rules.
    func pauseUABuiltIns() {
        for i in state.rules.indices where Self.uaRuleIDs.contains(state.rules[i].id) { state.rules[i].paused = true }
        save()
    }

    private var uaInstalled: Bool { FileManager.default.fileExists(atPath: UAWatchdog.folder) }

    /// Rules whose software is installed, in order.
    private var applicableRules: [HoeRule] {
        let installed = uaInstalled
        return state.rules.filter { r in r.requiresPath.map { $0 == UAWatchdog.folder ? installed : FileManager.default.fileExists(atPath: $0) } ?? true }
    }

    private func save() { state.save(to: defaults) }

    @objc private func appSwitched(_ n: Notification) {
        let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if let id = app?.bundleIdentifier, Self.forceQuitApps.contains(id) { forceQuitWindowAt = Date() }
    }

    func tick(now: Date) {
        guard enabled, !inFlight, now.timeIntervalSince(lastSample) >= sampleSeconds - 0.5 else { return }
        lastSample = now
        if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, Self.forceQuitApps.contains(id) { forceQuitWindowAt = now }
        inFlight = true
        let interest = hoes.interest, gen = generation, uid = String(getuid()), facts = facts
        queue.async { [weak self] in
            let ps = Shell.run("/bin/ps", ["-U", uid, "-o", "pid=,ppid=,%cpu=,command=", "-ww"])
            let at = Date()   // when ps returned, not when the tick fired
            let jobs = LostSouls.launchdJobs(fromLaunchctlList: Shell.run("/bin/launchctl", ["list"]) ?? "")
            var details: [Int: Hoes.Detail] = [:]
            for line in (ps ?? "").split(separator: "\n") {
                let f = line.split(maxSplits: 3, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
                guard f.count == 4, let pid = Int(f[0]), let cpu = Double(f[2]),
                      interest.wants(pid: pid, cpu: cpu, command: String(f[3])) else { continue }
                details[pid] = facts.detail(pid, launchdJobs: jobs)
            }
            DispatchQueue.main.async { self?.apply(ps: ps, details: details, at: at, generation: gen) }
        }
    }

    private func apply(ps: String?, details: [Int: Hoes.Detail], at now: Date, generation gen: Int) {
        inFlight = false
        guard enabled, gen == generation else { return }
        guard let ps else { lastError = "Couldn't list processes"; return }
        if lastError == "Couldn't list processes" { lastError = nil }
        let front = NSWorkspace.shared.frontmostApplication
        let r = hoes.record(ps: ps, at: now, details: details, rules: applicableRules, hidden: state.hiddenKeys,
                            frontmostPID: front.map { Int($0.processIdentifier) },
                            frontmostBundle: front?.bundleURL.map { $0.path + "/" },
                            forceQuitWindowAt: forceQuitWindowAt, selfPID: Int(getpid()))
        current = r.hoes
        var lines = r.warnings
        for fq in r.forceQuits {
            let why = fq.evidence.isEmpty ? "" : " [" + fq.evidence.map(\.rawValue).joined(separator: ", ") + "]"
            lines.append("FORCE-QUIT \(fq.name) pid=\(fq.pid) after \(Int(fq.hotSeconds / 60)) min at \(Int(fq.meanCPU.rounded()))%\(why)")
            switch state.learn(fq, now: now) {
            case .suggested(let s):
                lines.append("SUGGESTED auto-kill \(s.name) at ≥\(s.threshold)% for \(s.minutes) min")
                notifier.post(title: "Hoes", body: s.notification)
            case .tightened(let rule):
                lines.append("RULE tightened \(rule.name): \(rule.summary)")
                notifier.post(title: "Hoes", body: "You ended \(fq.name) again, so its rule now ends it at \(rule.summary)")
            case .unchanged, .skipped: break
            }
        }
        for rs in r.respawns {
            lines.append("RESPAWNED \(rs.key)" + (rs.launchdLabel.map { " (\($0))" } ?? ""))
            state.noteRespawn(rs)
        }
        if !r.forceQuits.isEmpty || !r.respawns.isEmpty { save() }
        append(lines, to: logURL, at: now)
        for d in r.due { autoKill(d) }
    }

    /// Is `pid` still this exact process, and yours? nil when nothing has that PID.
    private static func verify(pid: Int, start: Date) -> Bool? {
        guard let info = bsdInfo(pid_t(pid)) else { return nil }
        return abs(startDate(info).timeIntervalSince(start)) < 1 && info.pbi_uid == getuid()
    }

    /// SIGKILL after 5 s if the same process is still alive.
    private func killLater(pid: Int, start: Date) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard Self.verify(pid: pid, start: start) == true else { return }
            if kill(pid_t(pid), SIGKILL) == 0 { log.notice("SIGKILLed [\(pid)]") }
        }
    }

    private func autoKill(_ d: Hoes.Due) {
        guard let rule = state.rules.first(where: { $0.id == d.ruleID }), Self.verify(pid: d.pid, start: d.start) == true else { return }
        hoes.markEnded(pid: d.pid, start: d.start, byRule: true)
        guard kill(pid_t(d.pid), rule.action == .kill ? SIGKILL : SIGTERM) == 0 else {
            if errno == EPERM { lastError = "Not allowed to end \(d.name) [\(d.pid)]" }
            return
        }
        if rule.action == .terminate { killLater(pid: d.pid, start: d.start) }
        log.notice("rule \(rule.id, privacy: .public) ended \(d.name, privacy: .public) [\(d.pid)]")
        let isUA = Self.uaRuleIDs.contains(rule.id)
        append([Hoes.killMessage(d, rule: rule)], to: logURL)
        if isUA { append([UAWatchdog.killMessage(d, rule: rule)], to: uaLogURL) }
        let restart = rule.restart(after: d.command)
        if let label = restart {
            let target = "gui/\(getuid())/\(label)"
            queue.async { [weak self] in
                _ = Shell.run("/bin/launchctl", ["kickstart", "-k", target])
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.append(["kickstarted \(label)"], to: self.logURL)
                    if isUA { self.append([UAWatchdog.kickstartMessage], to: self.uaLogURL) }
                }
            }
        }
        notifier.post(title: "Hoes", body: isUA ? UAWatchdog.notification(label: d.name, audioRestored: restart != nil)
                      : "Ended runaway \(d.name) (\(Int(d.meanCPU.rounded()))% for \(Int(d.seconds / 60)) min)")
        onSweep?(.hatTip)
    }

    private func append(_ messages: [String], to url: URL, at date: Date = Date()) {
        let text = messages.map { UAWatchdogLog.line($0, at: date) }.joined()
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
    }

    // MARK: - Menu

    var title: String {
        guard enabled else { return "Hoes — Off" }
        var t = current.isEmpty ? "Hoes — none on the clock" : "Hoes — \(current.count) on the clock"
        let n = state.suggestions.count
        if n > 0 { t += " · \(n) suggestion\(n == 1 ? "" : "s")" }
        return t
    }
    var warning: String? { lastError }
    var needsAttention: Bool { enabled && (!current.isEmpty || !state.suggestions.isEmpty) }

    func addMenuItems(to menu: NSMenu) {
        warningItems().forEach(menu.addItem)
        let toggle = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self; toggle.state = enabled ? .on : .off
        menu.addItem(toggle)
        if !current.isEmpty || !state.suggestions.isEmpty { menu.addItem(.separator()) }
        let hottest = current.sorted { $0.meanCPU > $1.meanCPU }
        for h in hottest.prefix(menuLimit) {
            let row = NSMenuItem(title: "\(h.name) [\(h.pid)]  —  \(Int(h.meanCPU.rounded()))% for \(h.minutes) min",
                                 action: nil, keyEquivalent: "")
            let sub = NSMenu()
            sub.addItem(item("End", #selector(endHoe(_:)), h.pid))
            sub.addItem(item("Ignore", #selector(ignoreHoe(_:)), h.pid))
            row.submenu = sub
            menu.addItem(row)
        }
        if hottest.count > menuLimit { menu.addItem(disabled("and \(hottest.count - menuLimit) more…")) }
        for s in state.suggestions {
            let row = NSMenuItem(title: s.prompt, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            sub.addItem(item("Yes", #selector(acceptSuggestion(_:)), s.key))
            let adjust = NSMenuItem(title: "Adjust", action: nil, keyEquivalent: "")
            adjust.submenu = choices(threshold: s.threshold, minutes: s.minutes, id: s.key,
                                     #selector(suggestionThreshold(_:)), #selector(suggestionMinutes(_:)))
            sub.addItem(adjust)
            sub.addItem(item("No", #selector(declineSuggestion(_:)), s.key))
            row.submenu = sub
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let rules = NSMenuItem(title: "Rules", action: nil, keyEquivalent: "")
        rules.submenu = rulesMenu()
        menu.addItem(rules)
        if !state.ignored.isEmpty {
            let ig = NSMenuItem(title: "Ignored", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            sub.addItem(disabled("Click to stop ignoring"))
            for i in state.ignored {
                sub.addItem(item(i.hidden ? i.name : "\(i.name) (not suggested)", #selector(unignore(_:)), i.key))
            }
            ig.submenu = sub
            menu.addItem(ig)
        }
        if FileManager.default.fileExists(atPath: logURL.path) {
            let open = NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
        }
    }

    private func rulesMenu() -> NSMenu {
        let m = NSMenu()
        let shown = applicableRules
        if shown.isEmpty { m.addItem(disabled("No rules yet")) }
        for r in shown {
            var title = "\(r.name) — \(r.summary)"
            if r.builtIn { title += " (built-in)" }
            if r.paused { title += " (paused)" }
            if let t = r.tightenedAt, Date().timeIntervalSince(t) < 24 * 3600 { title += " (tightened)" }
            let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = choices(threshold: r.threshold, minutes: r.minutes, id: r.id, #selector(ruleThreshold(_:)), #selector(ruleMinutes(_:)))
            if r.restartLabel != nil {
                let i = item("Restart After Kill", #selector(toggleRestart(_:)), r.id); i.state = r.restartAfterKill ? .on : .off
                sub.addItem(i)
            }
            let front = item("Skip While In Front", #selector(toggleFront(_:)), r.id); front.state = r.skipWhenFrontmost ? .on : .off
            sub.addItem(front)
            let paused = item("Paused", #selector(togglePaused(_:)), r.id); paused.state = r.paused ? .on : .off
            sub.addItem(paused)
            if !r.builtIn { sub.addItem(.separator()); sub.addItem(item("Delete", #selector(deleteRule(_:)), r.id)) }
            row.submenu = sub
            m.addItem(row)
        }
        if uaInstalled {
            m.addItem(.separator())
            m.addItem(disabled("UA Watchdog"))
            let text = (try? String(contentsOf: uaLogURL, encoding: .utf8)) ?? ""
            for line in UAWatchdogLog.summary(text, now: Date()) { m.addItem(indented(disabled(line))) }
        }
        return m
    }

    /// Threshold ▸ and Duration ▸ for a rule or a suggestion; the current value is always listed.
    private func choices(threshold: Int, minutes: Int, id: String, _ setT: Selector, _ setM: Selector) -> NSMenu {
        let m = NSMenu()
        let t = NSMenuItem(title: "Threshold", action: nil, keyEquivalent: ""), tm = NSMenu()
        for v in Set(HoeRule.thresholdChoices + [threshold]).sorted() {
            let i = item("\(v)%", setT, id); i.tag = v; i.state = v == threshold ? .on : .off
            tm.addItem(i)
        }
        t.submenu = tm
        let d = NSMenuItem(title: "Duration", action: nil, keyEquivalent: ""), dm = NSMenu()
        for v in Set(HoeRule.minuteChoices + [minutes]).sorted() {
            let i = item(v == 0 ? "On sight" : "\(v) min", setM, id); i.tag = v; i.state = v == minutes ? .on : .off
            dm.addItem(i)
        }
        d.submenu = dm
        m.addItem(t); m.addItem(d)
        return m
    }

    private func item(_ title: String, _ action: Selector, _ object: Any) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self; i.representedObject = object
        return i
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    // MARK: - Actions

    private func hoe(for sender: NSMenuItem) -> Hoes.Hoe? {
        guard let pid = sender.representedObject as? Int else { return nil }
        return current.first { $0.pid == pid }
    }

    private func editRule(_ sender: NSMenuItem, _ change: (inout HoeRule) -> Void) {
        guard let id = sender.representedObject as? String, let i = state.rules.firstIndex(where: { $0.id == id }) else { return }
        change(&state.rules[i])
        append(["RULE changed \(state.rules[i].name): \(state.rules[i].summary)" + (state.rules[i].paused ? " (paused)" : "")], to: logURL)
        save()
    }

    private func editSuggestion(_ sender: NSMenuItem, _ change: (inout HoesState.Suggestion) -> Void) {
        guard let key = sender.representedObject as? String, let i = state.suggestions.firstIndex(where: { $0.key == key }) else { return }
        change(&state.suggestions[i])
        save()
    }

    @objc private func toggleEnabled() { enabled.toggle() }
    @objc private func openLog() { NSWorkspace.shared.open(logURL) }

    /// SIGTERM, then SIGKILL after 5 s; a sure sign you wanted it gone.
    @objc private func endHoe(_ sender: NSMenuItem) {
        guard let h = hoe(for: sender) else { return }
        current.removeAll { $0.pid == h.pid }
        switch Self.verify(pid: h.pid, start: h.start) {
        case nil: return
        case false?: lastError = "\(h.name) changed — not ended"; return
        case true?: break
        }
        hoes.markEnded(pid: h.pid, start: h.start, byRule: false)
        guard kill(pid_t(h.pid), SIGTERM) == 0 else {
            if errno == EPERM { lastError = "Not allowed to end \(h.name) [\(h.pid)]" }
            return
        }
        lastError = nil
        append(["KILLED \(h.name) pid=\(h.pid) (ended from the menu at \(Int(h.meanCPU.rounded()))% for \(h.minutes) min)"], to: logURL)
        onSweep?(.hatTip)
        killLater(pid: h.pid, start: h.start)
    }

    @objc private func ignoreHoe(_ sender: NSMenuItem) {
        guard let h = hoe(for: sender) else { return }
        state.ignore(key: h.key, name: h.name)
        current.removeAll { $0.key == h.key }
        append(["IGNORED \(h.name) (\(h.key))"], to: logURL)
        save()
    }

    @objc private func acceptSuggestion(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let r = state.accept(key: key) else { return }
        append(["RULE added \(r.name): \(r.summary)"], to: logURL)
        save()
    }

    @objc private func declineSuggestion(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        state.decline(key: key)
        append(["DECLINED \(key)"], to: logURL)
        save()
    }

    @objc private func suggestionThreshold(_ sender: NSMenuItem) { editSuggestion(sender) { $0.threshold = sender.tag } }
    @objc private func suggestionMinutes(_ sender: NSMenuItem) { editSuggestion(sender) { $0.minutes = sender.tag } }
    @objc private func ruleThreshold(_ sender: NSMenuItem) { editRule(sender) { $0.threshold = sender.tag } }
    @objc private func ruleMinutes(_ sender: NSMenuItem) { editRule(sender) { $0.minutes = sender.tag } }
    @objc private func toggleRestart(_ sender: NSMenuItem) { editRule(sender) { $0.restartAfterKill.toggle() } }
    @objc private func toggleFront(_ sender: NSMenuItem) { editRule(sender) { $0.skipWhenFrontmost.toggle() } }
    @objc private func togglePaused(_ sender: NSMenuItem) { editRule(sender) { $0.paused.toggle() } }

    @objc private func deleteRule(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, state.deleteRule(id: id) else { return }
        append(["RULE deleted \(id)"], to: logURL)
        save()
    }

    @objc private func unignore(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        state.unignore(key: key)
        append(["UNIGNORED \(key)"], to: logURL)
        save()
    }
}
