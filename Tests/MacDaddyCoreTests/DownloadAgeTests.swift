// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MacDaddyCore

final class DownloadAgeTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 10_000_000)
    let day: TimeInterval = 86_400

    func item(_ name: String, ageDays: Double?) -> DownloadItem {
        DownloadItem(url: URL(fileURLWithPath: "/tmp/\(name)"),
                     modified: ageDays.map { now.addingTimeInterval(-$0 * day) })
    }

    func testOnlyStrictlyOlderThanTheCutoff() {
        let items = [item("old", ageDays: 31), item("edge", ageDays: 30), item("new", ageDays: 1)]
        XCTAssertEqual(DownloadAge.expired(items, daysToKeep: 30, now: now).map(\.lastPathComponent), ["old"])
    }

    func testUnknownDateIsKept() {
        XCTAssertEqual(DownloadAge.expired([item("mystery", ageDays: nil)], daysToKeep: 7, now: now), [])
    }

    func testEmptyFolder() {
        XCTAssertEqual(DownloadAge.expired([], daysToKeep: 7, now: now), [])
    }

    func date(_ ageDays: Double?) -> Date? { ageDays.map { now.addingTimeInterval(-$0 * day) } }

    func testOldModificationButAddedYesterdayIsKept() {
        let i = DownloadItem(url: URL(fileURLWithPath: "/tmp/unzipped"), modified: date(400), added: date(1))
        XCTAssertEqual(i.date, date(1))
        XCTAssertEqual(DownloadAge.expired([i], daysToKeep: 30, now: now), [])
    }

    func testBothDatesOldIsExpired() {
        let i = DownloadItem(url: URL(fileURLWithPath: "/tmp/stale"), modified: date(40), added: date(35))
        XCTAssertEqual(DownloadAge.expired([i], daysToKeep: 30, now: now).map(\.lastPathComponent), ["stale"])
    }

    func testMissingAddedDateFallsBackToModified() {
        let old = DownloadItem(url: URL(fileURLWithPath: "/tmp/old"), modified: date(40), added: nil)
        let new = DownloadItem(url: URL(fileURLWithPath: "/tmp/new"), modified: date(2), added: nil)
        XCTAssertEqual(DownloadAge.expired([old, new], daysToKeep: 30, now: now).map(\.lastPathComponent), ["old"])
    }

    func testMissingModifiedDateUsesAdded() {
        let i = DownloadItem(url: URL(fileURLWithPath: "/tmp/x"), modified: nil, added: date(40))
        XCTAssertEqual(DownloadAge.expired([i], daysToKeep: 30, now: now).count, 1)
    }
}
