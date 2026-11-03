// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import LauncherCore

final class MenuCraneMigrationTests: XCTestCase {
    let old: [String: Any] = [
        "HotkeyKeyCode": 49, "HotkeyModifiers": 256, "PanelX": 305.0, "PanelTop": 408.0,
        "UnitSystem": "metric", "SkinTone": 2,
        "IconStyle": "crane", "NSStatusItem Preferred Position MenuCrane": 351,
    ]

    func testRenamesEveryKeyAndTurnsTheLauncherOn() {
        let v = MenuCraneMigration.values(old: old, existing: [], installed: true)
        XCTAssertEqual(v[HotkeySettings.keyCodeKey] as? Int, 49)
        XCTAssertEqual(v[HotkeySettings.modifiersKey] as? Int, 256)
        XCTAssertEqual(v[PanelPlacement.xKey] as? Double, 305)
        XCTAssertEqual(v[PanelPlacement.topKey] as? Double, 408)
        XCTAssertEqual(v[LauncherKeys.unitSystem] as? String, "metric")
        XCTAssertEqual(v[LauncherKeys.skinTone] as? Int, 2)
        XCTAssertEqual(v[LauncherKeys.enabled] as? Bool, true)
        XCTAssertEqual(v.count, 7, "IconStyle and the status-item position stay behind")
    }

    func testNeverOverwritesMacDaddysOwnValues() {
        let v = MenuCraneMigration.values(old: old, existing: [LauncherKeys.unitSystem, LauncherKeys.enabled], installed: true)
        XCTAssertNil(v[LauncherKeys.unitSystem])
        XCTAssertNil(v[LauncherKeys.enabled])
        XCTAssertNotNil(v[LauncherKeys.skinTone])
    }

    func testNoMenuCraneLeavesTheLauncherOff() {
        XCTAssertTrue(MenuCraneMigration.values(old: [:], existing: [], installed: false).isEmpty)
    }

    func testAnInstalledMenuCraneWithNoSettingsStillCounts() {
        let v = MenuCraneMigration.values(old: [:], existing: [], installed: true)
        XCTAssertEqual(v[LauncherKeys.enabled] as? Bool, true)
    }

    func testApplyOnceRunsOnce() throws {
        // applyOnce reads the domain back by name, which a path-named
        // scratch suite can't do, so this one uses a fixed domain: at most
        // one plist, reused, rather than one per run.
        let domain = "com.nicholaspsmith.MacDaddy.tests.migration"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let first = MenuCraneMigration.applyOnce(old: old, installed: true, to: defaults, domain: domain)
        XCTAssertEqual(first?.contains(LauncherKeys.enabled), true)
        XCTAssertTrue(defaults.bool(forKey: MenuCraneMigration.doneKey))
        defaults.set(false, forKey: LauncherKeys.enabled)   // the user turns it off afterwards
        XCTAssertNil(MenuCraneMigration.applyOnce(old: old, installed: true, to: defaults, domain: domain))
        XCTAssertFalse(defaults.bool(forKey: LauncherKeys.enabled))
    }

    func testCopyFilesSkipsExistingAndMissing() throws {
        let from = try Fixtures.tempDir(), to = try Fixtures.tempDir().appending(path: "Launcher")
        try Data("{\"🤓\":[\"nerd\"]}".utf8).write(to: from.appending(path: "aliases.json"))
        try Data("old".utf8).write(to: from.appending(path: "usage.json"))
        try FileManager.default.createDirectory(at: to, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: to.appending(path: "usage.json"))
        XCTAssertEqual(MenuCraneMigration.copyFiles(from: from, to: to), ["aliases.json"])
        XCTAssertEqual(try String(contentsOf: to.appending(path: "usage.json"), encoding: .utf8), "mine")
        XCTAssertEqual(MenuCraneMigration.copyFiles(from: from.appending(path: "nowhere"), to: to), [])
    }
}
