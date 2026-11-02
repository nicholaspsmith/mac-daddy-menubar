// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation

public struct AppEntry: Equatable, Sendable {
    public let name: String
    /// The app itself, symlinks resolved: what is opened and what the icon is read from.
    public let url: URL
    /// Where the index found it — for a Menumon app, the link in ~/Applications rather than
    /// the build folder it points into. Shown under the name and revealed in Finder.
    public let location: URL
    public let bundleID: String?
    /// Identity for de-duplication and usage: bundle id, else path.
    public var key: String { bundleID ?? url.path }
}

public final class AppIndex {
    public static var defaultRoots: [URL] {
        [URL(fileURLWithPath: "/Applications"),
         URL(fileURLWithPath: "/System/Applications"),
         FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")]
    }
    public static var defaultExtras: [URL] {
        [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
    }

    public private(set) var apps: [AppEntry] = []
    /// Bumped on every rebuild so providers know to refresh their match targets.
    public private(set) var generation = 0
    /// Paths skipped during the last rebuild, with the reason.
    public private(set) var skipped: [String] = []
    private let roots: [URL]
    private let extras: [URL]

    public init(roots: [URL] = AppIndex.defaultRoots, extras: [URL] = AppIndex.defaultExtras) {
        self.roots = roots
        self.extras = extras
        rebuild()
    }

    public func rebuild() {
        var found: [AppEntry] = []
        var seen = Set<String>()
        var skipped: [String] = []
        func add(_ url: URL) {
            let resolved = url.resolvingSymlinksInPath()
            guard FileManager.default.fileExists(atPath: resolved.path) else {
                skipped.append("\(url.path): broken link"); return
            }
            var name = FileManager.default.displayName(atPath: resolved.path)
            if name.hasSuffix(".app") { name.removeLast(4) }
            let isLink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
            let location = isLink ? url : resolved
            let entry = AppEntry(name: name, url: resolved, location: location,
                                 bundleID: Bundle(url: resolved)?.bundleIdentifier)
            if seen.insert(entry.key).inserted { found.append(entry) }
        }
        func walk(_ dir: URL, depth: Int) {
            let items: [URL]
            do {
                // Not .skipsHiddenFiles: that also drops entries with the Finder "hidden" flag,
                // which macOS sets on /Applications/Safari.app. Skip only dot-named entries.
                items = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                    .filter { !$0.lastPathComponent.hasPrefix(".") }
            } catch {
                skipped.append("\(dir.path): \(error.localizedDescription)"); return
            }
            for item in items.sorted(by: { $0.path < $1.path }) {
                if item.pathExtension == "app" { add(item); continue }
                var isDir: ObjCBool = false
                if depth < 1, FileManager.default.fileExists(atPath: item.resolvingSymlinksInPath().path, isDirectory: &isDir), isDir.boolValue {
                    walk(item, depth: depth + 1)
                }
            }
        }
        for root in roots { walk(root, depth: 0) }
        for extra in extras { add(extra) }
        for s in skipped { coreLog.info("app index skipped \(s, privacy: .public)") }
        apps = found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.skipped = skipped
        generation += 1
    }
}
