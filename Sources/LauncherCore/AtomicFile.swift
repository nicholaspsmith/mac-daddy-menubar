// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation

public enum AppSupport {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/MacDaddy/Launcher")
    }
}

public enum AtomicFile {
    /// Write to a temporary file and rename over `url`, so a crash can't leave half a file.
    public static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

/// Calls `onChange` (debounced 0.2 s, on main) when entries in `directory` are added, renamed or
/// removed — which is what an atomic save of a file inside it looks like.
public final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    public init?(directory: URL, onChange: @escaping () -> Void) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            self?.pending?.cancel()
            let work = DispatchWorkItem(block: onChange)
            self?.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    deinit { source?.cancel() }
}
