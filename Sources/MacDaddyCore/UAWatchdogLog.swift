// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// `~/.local/state/ua-watchdog.log`, kept in the old agent's format so its
/// history carries on (and Apollo Monitor can still read it):
///
///     2026-07-30 16:16:07  KILLED orphaned UA Mixer Helper pid=32329 cpu=100.0% (fast-path: PPID=1)
///     2026-07-30 16:16:07  KILLED runaway UAD Meter pid=32331 cpu=100.0% (>=90% x 2 ticks)
///     2026-07-30 16:16:07  WARN UAD Meter pid=32331 cpu=100.0% (tick 1/2 >=90%)
///     2026-07-30 16:16:07  kickstarted UA mixer engine to restore audio path
///
/// A local-time stamp, two spaces, then the message.
public enum UAWatchdogLog {
    public struct Event: Equatable {
        public enum Kind: Equatable { case killed, warn, other }
        public let date: Date
        public let kind: Kind
        /// The process label on KILLED/WARN lines; empty otherwise.
        public let label: String
    }

    public static let dateFormat = "yyyy-MM-dd HH:mm:ss"

    private static func formatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = dateFormat
        return f
    }

    /// One log line, newline included.
    public static func line(_ message: String, at date: Date) -> String {
        "\(formatter().string(from: date))  \(message)\n"
    }

    /// nil unless the line starts with a timestamp.
    public static func parseLine(_ line: String, formatter f: DateFormatter? = nil) -> Event? {
        guard line.count > 21, let date = (f ?? formatter()).date(from: String(line.prefix(19))) else { return nil }
        let message = line.dropFirst(19).trimmingCharacters(in: .whitespaces)
        if message.hasPrefix("KILLED") { return Event(date: date, kind: .killed, label: killedLabel(message)) }
        if message.hasPrefix("WARN") { return Event(date: date, kind: .warn, label: labelAfterFirstWord(message)) }
        return Event(date: date, kind: .other, label: "")
    }

    public static func events(_ text: String) -> [Event] {
        let f = formatter()
        return text.split(separator: "\n").compactMap { parseLine(String($0), formatter: f) }
    }

    /// The latest KILLED line by its stamp, not its position, so a line out of
    /// order (a DST fall-back) can't pass a stale kill off as the latest.
    public static func lastKill(_ text: String) -> Event? {
        events(text).filter { $0.kind == .killed }.max { $0.date < $1.date }
    }

    public static func killsToday(_ text: String, now: Date, calendar: Calendar = .current) -> Int {
        events(text).filter { $0.kind == .killed && calendar.isDate($0.date, inSameDayAs: now) }.count
    }

    /// "just now", "N min ago", "N h ago" (under two days), "N d ago".
    public static func ago(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 48 * 3600 { return "\(s / 3600) h ago" }
        return "\(s / 86400) d ago"
    }

    /// The menu's lines: the last kill and today's count, or "No kills yet".
    public static func summary(_ text: String, now: Date) -> [String] {
        guard let last = lastKill(text) else { return ["No kills yet"] }
        return ["Last kill: \(last.label), \(ago(now.timeIntervalSince(last.date)))",
                "Kills today: \(killsToday(text, now: now))"]
    }

    /// "KILLED [orphaned|runaway] <label> pid=…" → the label.
    private static func killedLabel(_ message: String) -> String {
        var rest = message.dropFirst("KILLED".count).trimmingCharacters(in: .whitespaces)
        for q in ["orphaned ", "runaway "] where rest.hasPrefix(q) { rest = String(rest.dropFirst(q.count)); break }
        return String(rest.prefix(upTo: rest.range(of: " pid=")?.lowerBound ?? rest.endIndex))
    }

    /// "WARN <label> pid=…" → the label.
    private static func labelAfterFirstWord(_ message: String) -> String {
        guard let space = message.firstIndex(of: " ") else { return "" }
        let rest = message[message.index(after: space)...]
        return String(rest.prefix(upTo: rest.range(of: " pid=")?.lowerBound ?? rest.endIndex))
    }
}
