// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MacDaddyCore

final class SettingsMigrationTests: XCTestCase {
    func testCopiesBothAppsIntoNamespacedKeys() {
        let swept = Date(timeIntervalSince1970: 5_000)
        let target = MemoryStore()
        let tracker = MemoryStore(["enabled": false, "intervalSeconds": 30, "target.photoanalysisd": false])
        let downloads = MemoryStore(["enabled": true, "daysToKeep": 14, "lastSweep": swept])
        _ = SettingsMigration.run(target: target, tracker: tracker, downloads: downloads)
        XCTAssertEqual(target.values["tracker.enabled"] as? Bool, false)
        XCTAssertEqual(target.values["tracker.intervalSeconds"] as? Int, 30)
        XCTAssertEqual(target.values["tracker.target.photoanalysisd"] as? Bool, false)
        XCTAssertNil(target.values["tracker.target.mediaanalysisd"])   // absent stays absent → default
        XCTAssertEqual(target.values["downloads.daysToKeep"] as? Int, 14)
        XCTAssertEqual(target.values["downloads.lastSweep"] as? Date, swept)
        XCTAssertEqual(target.values[SettingsMigration.versionKey] as? Int, 1)
    }

    func testRunsOnlyOnce() {
        let target = MemoryStore([SettingsMigration.versionKey: 1])
        _ = SettingsMigration.run(target: target, tracker: MemoryStore(["intervalSeconds": 60]), downloads: nil)
        XCTAssertNil(target.values["tracker.intervalSeconds"])
    }

    func testNeverOverwritesAValueAlreadySet() {
        let target = MemoryStore(["downloads.daysToKeep": 90])
        _ = SettingsMigration.run(target: target, tracker: nil, downloads: MemoryStore(["daysToKeep": 7]))
        XCTAssertEqual(target.values["downloads.daysToKeep"] as? Int, 90)
    }

    func testWrongTypesFallBackAndTheRestMigrate() {
        let target = MemoryStore()
        let log = SettingsMigration.run(
            target: target,
            tracker: MemoryStore(["intervalSeconds": "thirty", "enabled": true]),
            downloads: MemoryStore(["lastSweep": 12345, "daysToKeep": 60]))
        XCTAssertNil(target.values["tracker.intervalSeconds"])
        XCTAssertEqual(target.values["tracker.enabled"] as? Bool, true)
        XCTAssertNil(target.values["downloads.lastSweep"])
        XCTAssertEqual(target.values["downloads.daysToKeep"] as? Int, 60)
        XCTAssertTrue(log.contains { $0.contains("intervalSeconds") })
        XCTAssertEqual(target.values[SettingsMigration.versionKey] as? Int, 1)
    }
}
