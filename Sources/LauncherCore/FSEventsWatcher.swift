// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import CoreServices
import Foundation

/// Calls `onChange` on the main queue when anything under `paths` changes (coalesced by `latency`).
public final class FSEventsWatcher {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let latency: TimeInterval
    private let onChange: () -> Void

    public init(paths: [String], latency: TimeInterval = 1, onChange: @escaping () -> Void) {
        self.paths = paths
        self.latency = latency
        self.onChange = onChange
    }

    public func start() {
        guard stream == nil else { return }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        guard let s = FSEventStreamCreate(nil, callback, &ctx, paths as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
                                          FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)) else {
            coreLog.error("FSEvents stream could not be created for \(self.paths.joined(separator: ", "), privacy: .public)")
            return
        }
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        stream = s
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }
}
