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

/// The icon: Mac Daddy himself, or a plain symbol in the same colours.
enum IconStyle: String, CaseIterable {
    case character, symbol
    var title: String { self == .character ? "Mac Daddy" : "Plain Symbol" }
    private static let key = "iconStyle"
    static var current: IconStyle {
        get { UserDefaults.standard.string(forKey: key).flatMap(IconStyle.init) ?? .character }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

final class App: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController!
    private var yieldClient: YieldClient!
    private let notifier = Notifier()
    private lazy var processWatch = ProcessWatch(notifier: notifier)
    private let tracker = TrackerKiller()
    private lazy var downloads = DownloadSweeper(notifier: notifier)
    private let reaper = Reaper()
    private var lastFlourish: (Flourish, Date)?

    private var cleanupDuties: [Duty] { [tracker, downloads, reaper] }
    private var allDuties: [Duty] { [processWatch, tracker, downloads, reaper] }

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrate()
        retireReaperAgent()
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
        redraw()
    }

    private func tick() {
        let now = Date()
        allDuties.forEach { $0.tick(now: now) }
        redraw()
    }

    private func migrate() {
        let lines = SettingsMigration.run(
            target: UserDefaults.standard,
            tracker: UserDefaults(suiteName: SettingsMigration.trackerDomain),
            downloads: UserDefaults(suiteName: SettingsMigration.downloadsDomain))
        lines.forEach { log.notice("migration: \($0, privacy: .public)") }
    }

    /// The reaper used to be a launchd agent; Mac Daddy does its job now.
    private func retireReaperAgent() {
        let label = "com.nicholassmith.godot-headless-reaper"
        let out = Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        log.notice("reaper agent bootout: \(out == nil ? "not loaded" : "unloaded", privacy: .public)")
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
            anyCleanupEnabled: tracker.enabled || downloads.enabled || reaper.enabled,
            lastFlourish: lastFlourish, now: Date())
        switch IconStyle.current {
        case .character:
            controller.setIcon(CharacterIcon.macDaddy(level: Self.level(mood.level), asleep: mood.asleep,
                                                      flourish: mood.flourish.map(Self.flourish)))
        case .symbol:
            let color: NSColor
            switch mood.level {
            case .cool: color = mood.asleep ? .systemGray : .systemPurple
            case .sweating: color = .systemOrange
            case .redHot: color = .systemRed
            }
            controller.setIcon(MeterIcon.symbol("sparkles", color: color))
        }
    }

    private static func level(_ l: MoodLevel) -> MacDaddyLevel {
        switch l { case .cool: return .cool; case .sweating: return .sweating; case .redHot: return .redHot }
    }
    private static func flourish(_ f: Flourish) -> MacDaddyFlourish {
        switch f { case .hatTip: return .hatTip; case .chainGlint: return .chainGlint }
    }

    private func buildMenu(_ menu: NSMenu) {
        processWatch.addMenuItems(to: menu)
        menu.addItem(.separator())
        tracker.addMenuItems(to: menu)
        downloads.addMenuItems(to: menu)
        reaper.addMenuItems(to: menu)
        menu.addItem(.separator())

        let icon = NSMenuItem(title: "Icon", action: nil, keyEquivalent: "")
        let im = NSMenu()
        for style in IconStyle.allCases {
            let i = NSMenuItem(title: style.title, action: #selector(pickIcon(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = style.rawValue; i.state = style == IconStyle.current ? .on : .off
            im.addItem(i)
        }
        icon.submenu = im
        menu.addItem(icon)

        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self; login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(AppVersion.menuItem())
        menu.addItem(NSMenuItem(title: "Quit Mac Daddy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func pickIcon(_ s: NSMenuItem) {
        guard let raw = s.representedObject as? String, let style = IconStyle(rawValue: raw) else { return }
        IconStyle.current = style
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
