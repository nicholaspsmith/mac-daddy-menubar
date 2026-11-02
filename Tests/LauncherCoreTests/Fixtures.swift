// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation
@testable import LauncherCore

enum Fixtures {
    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    static var emojiJSON: URL { packageRoot.appending(path: "Resources/bundle/emoji.json") }
    static func emojiStore() throws -> EmojiStore { try EmojiStore(data: Data(contentsOf: emojiJSON)) }

    static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "launcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A minimal `.app` directory; `bundleID` nil leaves out Info.plist entirely.
    @discardableResult
    static func makeApp(_ name: String, in dir: URL, bundleID: String?) throws -> URL {
        let app = dir.appending(path: "\(name).app")
        let contents = app.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        if let bundleID {
            let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": name, "CFBundlePackageType": "APPL"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appending(path: "Info.plist"))
        }
        return app
    }
}
