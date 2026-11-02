// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import LauncherCore

final class AppIndexTests: XCTestCase {
    func testScansRootsOneLevelDeepResolvesLinksAndDedupes() throws {
        let fm = FileManager.default
        let a = try Fixtures.tempDir(), b = try Fixtures.tempDir(), elsewhere = try Fixtures.tempDir()
        try Fixtures.makeApp("Real", in: a, bundleID: "com.test.real")
        let utilities = a.appending(path: "Utilities")
        try fm.createDirectory(at: utilities, withIntermediateDirectories: true)
        try Fixtures.makeApp("Tool", in: utilities, bundleID: "com.test.tool")
        let deep = a.appending(path: "Folder/Deeper")
        try fm.createDirectory(at: deep, withIntermediateDirectories: true)
        try Fixtures.makeApp("TooDeep", in: deep, bundleID: "com.test.deep")
        try Fixtures.makeApp("NoID", in: a, bundleID: nil)
        // b: a symlink to an app that lives elsewhere (how ~/Applications holds Menumon apps),
        // a duplicate of Real by bundle id, and a broken link.
        let linked = try Fixtures.makeApp("Linked", in: elsewhere, bundleID: "com.test.linked")
        try fm.createSymbolicLink(at: b.appending(path: "Linked.app"), withDestinationURL: linked)
        try Fixtures.makeApp("Real Copy", in: b, bundleID: "com.test.real")
        try fm.createSymbolicLink(at: b.appending(path: "Gone.app"), withDestinationURL: elsewhere.appending(path: "Missing.app"))

        let index = AppIndex(roots: [a, b], extras: [])
        let names = index.apps.map(\.name)
        XCTAssertEqual(Set(names), ["Real", "Tool", "NoID", "Linked"])
        let linkedEntry = index.apps.first { $0.name == "Linked" }
        XCTAssertEqual(linkedEntry?.url.resolvingSymlinksInPath(), linked.resolvingSymlinksInPath())
        // Shown and revealed where it was found, not where the link points.
        // (Compared by folder, resolved: the temp dir itself is /var → /private/var.)
        XCTAssertEqual(linkedEntry?.location.lastPathComponent, "Linked.app")
        XCTAssertEqual(linkedEntry?.location.deletingLastPathComponent().resolvingSymlinksInPath(),
                       b.resolvingSymlinksInPath())
        let real = index.apps.first { $0.name == "Real" }
        XCTAssertEqual(real?.location, real?.url)
        XCTAssertNil(index.apps.first { $0.name == "NoID" }?.bundleID)
        XCTAssertTrue(index.skipped.contains { $0.contains("Gone.app") })
        XCTAssertEqual(names, names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    func testUnreadableRootIsSkipped() {
        let index = AppIndex(roots: [URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")], extras: [])
        XCTAssertEqual(index.apps, [])
    }

    func testRebuildBumpsGenerationAndSeesChanges() throws {
        let dir = try Fixtures.tempDir()
        let index = AppIndex(roots: [dir], extras: [])
        let g = index.generation
        try Fixtures.makeApp("New", in: dir, bundleID: "com.test.new")
        index.rebuild()
        XCTAssertEqual(index.apps.map(\.name), ["New"])
        XCTAssertEqual(index.generation, g + 1)
    }

    func testExtrasAreIncluded() throws {
        let dir = try Fixtures.tempDir()
        let finder = try Fixtures.makeApp("Finder", in: dir, bundleID: "com.apple.finder")
        XCTAssertEqual(AppIndex(roots: [], extras: [finder]).apps.map(\.name), ["Finder"])
    }

    /// macOS marks /Applications/Safari.app (a link into the Safari cryptex) with the Finder
    /// "hidden" flag; it must still be indexed. Dot-named entries stay skipped.
    func testHiddenFlaggedLinkIsIndexedButDotEntriesAreNot() throws {
        let fm = FileManager.default
        let root = try Fixtures.tempDir(), elsewhere = try Fixtures.tempDir()
        let target = try Fixtures.makeApp("Browser", in: elsewhere, bundleID: "com.test.browser")
        let link = root.appending(path: "Browser.app")
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertEqual(lchflags(link.path, UInt32(UF_HIDDEN)), 0)
        try Fixtures.makeApp(".Secret", in: root, bundleID: "com.test.secret")

        XCTAssertEqual(AppIndex(roots: [root], extras: []).apps.map(\.name), ["Browser"])
    }
}
