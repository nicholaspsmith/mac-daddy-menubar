// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Darwin

/// `responsibility_get_pid_responsible_for_pid` is private libsystem API, so
/// it is looked up at runtime: if a macOS release drops it, Mac Daddy still
/// launches and Lost Souls just skips the responsibility exclusion.
public enum Responsibility {
    public static let symbol = "responsibility_get_pid_responsible_for_pid"
    private typealias Fn = @convention(c) (pid_t) -> pid_t

    /// `dlsym(RTLD_DEFAULT, name)`.
    public static func dlsymDefault(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    }

    /// The lookup, or nil when `find` can't resolve the symbol.
    public static func resolve(_ find: (String) -> UnsafeMutableRawPointer?) -> ((Int) -> Int?)? {
        guard let p = find(symbol) else { return nil }
        let fn = unsafeBitCast(p, to: Fn.self)
        return { pid in
            let r = fn(pid_t(pid))
            return r > 0 ? Int(r) : nil
        }
    }

    /// Resolved once per launch.
    public static let shared: ((Int) -> Int?)? = resolve(dlsymDefault)
}
