// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import os
@_exported import MacDaddyCore
import StatusItemKit

private let log = Logger(subsystem: "com.nicholaspsmith.MacDaddy", category: "app")

final class App: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController!
    private var yieldClient: YieldClient!
    private let notifier = Notifier()
    private lazy var processWatch = ProcessWatch(notifier: notifier)
    private let tracker = TrackerKiller()
    private lazy var downloads = DownloadSweeper(notifier: notifier)
    private lazy var lostSouls = LostSoulsDuty(notifier: notifier)
    private lazy var hoes = HoesDuty(notifier: notifier)
    private var lastFlourish: (Flourish, Date)?
    /// Once a minute, in his turn with the other animated mascots, he grins and
    /// a gold gleam crosses his teeth. Progress 0...1, linear; 0 when not grinning.
    private var minuteCue: MinuteCue!
    private var grin: CGFloat = 0
    private lazy var grinAnimation = IconAnimation(duration: CharacterIcon.macDaddyGrinDuration, frame: { [weak self] t in
        self?.grin = CGFloat(t / CharacterIcon.macDaddyGrinDuration)
        self?.redraw()
    }, completion: { [weak self] in
        self?.grin = 0
        self?.redraw()
    })

    private var cleanupDuties: [Duty] { [tracker, downloads, lostSouls, hoes] }
    private var allDuties: [Duty] { [processWatch, tracker, downloads, lostSouls, hoes] }

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrate()
        retireReaperAgent()
        retireUAWatchdogAgent()
        notifier.requestAuthorization()
        for d in allDuties {
            d.onSweep = { [weak self] f in self?.flourish(f) }
            d.onChange = { [weak self] in self?.redraw() }
        }
        controller = StatusItemController(
            pollInterval: 5,
            onPoll: { [weak self] in self?.tick() },
            onBuildMenu: { [weak self] menu in self?.buildMenu(menu) }
        )
        controller.start()
        yieldClient = YieldClient(item: controller)
        yieldClient.start()
        minuteCue = MinuteCue { [weak self] in
            guard Mode.load(from: .standard) == .pimp else { return }
            self?.grinAnimation.start()
        }
        minuteCue.start()
        redraw()
    }

    private func tick() {
        let now = Date()
        allDuties.forEach { $0.tick(now: now) }
        redraw()
    }

    private func migrate() {
        Mode.migrateIconStyle(in: .standard)
        let lines = SettingsMigration.run(
            target: UserDefaults.standard,
            tracker: UserDefaults(suiteName: SettingsMigration.trackerDomain),
            downloads: UserDefaults(suiteName: SettingsMigration.downloadsDomain))
        lines.forEach { log.notice("migration: \($0, privacy: .public)") }
    }

    /// The Godot reaper used to be a launchd agent; Lost Souls covers its job now.
    /// Kept as a harmless backstop in case an old install still has it loaded.
    private func retireReaperAgent() {
        let label = "com.nicholassmith.godot-headless-reaper"
        DispatchQueue.global(qos: .utility).async {
            let out = Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
            log.notice("reaper agent bootout: \(out == nil ? "not loaded" : "unloaded", privacy: .public)")
        }
    }

    /// The UA watchdog used to be a launchd agent; built-in Hoes rules do its job now.
    /// The first time, a deliberate "off" (`launchctl disable`, which outlives the
    /// plist) carries over: the UA rules start paused. Then the agent is booted out, as a backstop
    /// for an install that still has it loaded.
    private func retireUAWatchdogAgent() {
        let label = "com.nicholassmith.ua-watchdog", carriedKey = "uaWatchdog.agentStateCarried"
        let carried = UserDefaults.standard.bool(forKey: carriedKey)
        DispatchQueue.global(qos: .utility).async {
            let domain = "gui/\(getuid())"
            if !carried, let text = Shell.run("/bin/launchctl", ["print-disabled", domain]) {
                let off = UAWatchdog.isDisabled(label, printDisabled: text)
                DispatchQueue.main.async { [weak self] in
                    if off { UserDefaults.standard.set(false, forKey: "uaWatchdog.enabled"); self?.hoes.pauseUABuiltIns() }
                    UserDefaults.standard.set(true, forKey: carriedKey)
                    log.notice("ua-watchdog agent was \(off ? "disabled: duty off" : "enabled", privacy: .public)")
                }
            }
            let out = Shell.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
            log.notice("ua-watchdog agent bootout: \(out == nil ? "not loaded" : "unloaded", privacy: .public)")
        }
    }

    private func flourish(_ f: Flourish) {
        lastFlourish = (f, Date())
        redraw()
        DispatchQueue.main.asyncAfter(deadline: .now() + Mood.flourishDuration + 0.05) { [weak self] in self?.redraw() }
    }

    private func redraw() {
        guard let controller else { return }
        let mood = Mood.compute(
            fraction: processWatch.fraction,
            anyCleanupEnabled: tracker.enabled || downloads.enabled || lostSouls.enabled || hoes.enabled,
            lastFlourish: lastFlourish, now: Date())
        // Pimp Mode is Menu Pimp himself; Normal Mode a plain symbol in the same colours.
        switch Mode.load(from: .standard) {
        case .pimp:
            let level = Self.level(mood.level), flourish = mood.flourish.map(Self.flourish)
            // The illustrated art ships in the bundle; if it is ever missing, the code-drawn glyph stands in.
            if let art = Self.art {
                controller.setIcon(CharacterIcon.macDaddy(art: art, level: level, asleep: mood.asleep, flourish: flourish, grin: grin))
            } else {
                controller.setIcon(CharacterIcon.macDaddy(level: level, asleep: mood.asleep, flourish: flourish, grin: grin))
            }
        case .normal:
            let color: NSColor
            switch mood.level {
            case .cool: color = mood.asleep ? .systemGray : .systemPurple
            case .sweating: color = .systemOrange
            case .redHot: color = .systemRed
            }
            controller.setIcon(MeterIcon.symbol("sparkles", color: color))
        }
    }

    private static let art = MacDaddyArt.load(from: .main)

    private static func level(_ l: MoodLevel) -> MacDaddyLevel {
        switch l { case .cool: return .cool; case .sweating: return .sweating; case .redHot: return .redHot }
    }
    private static func flourish(_ f: Flourish) -> MacDaddyFlourish {
        switch f { case .hatTip: return .hatTip; case .chainGlint: return .chainGlint }
    }

    private func buildMenu(_ menu: NSMenu) {
        processWatch.addMenuItems(to: menu)
        menu.addItem(.separator())
        // Each cleanup duty is one summary line; its controls open as a submenu.
        cleanupDuties.forEach { menu.addItem($0.sectionItem()) }
        menu.addItem(.separator())

        let mode = Mode.load(from: .standard), terms = Terms(mode)
        let modeItem = NSMenuItem(title: terms.modeMenu, action: nil, keyEquivalent: "")
        let mm = NSMenu()
        for m in Mode.allCases {
            let i = NSMenuItem(title: terms.modeName(m), action: #selector(pickMode(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = m.rawValue; i.state = m == mode ? .on : .off
            mm.addItem(i)
        }
        modeItem.submenu = mm
        menu.addItem(modeItem)

        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self; login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(AppVersion.menuItem())
        menu.addItem(NSMenuItem(title: "Quit Mac Daddy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func pickMode(_ s: NSMenuItem) {
        guard let raw = s.representedObject as? String, let mode = Mode(rawValue: raw) else { return }
        mode.save(to: .standard)
        if mode == .normal { grinAnimation.cancel(); grin = 0 }
        redraw()
    }
    @objc private func toggleLogin() { LoginItem.toggle() }
}

// `--login on|off|status` and exit before any UI exists (install.sh uses it).
LoginCLI.runIfRequested()

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
