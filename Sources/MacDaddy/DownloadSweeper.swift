// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import StatusItemKit

/// Moves old top-level ~/Downloads items to the Trash (restorable). Was Download Recycler.
final class DownloadSweeper: NSObject, Duty {
    var onSweep: ((Flourish) -> Void)?
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let notifier: Notifier
    static let dayChoices = [7, 14, 30, 60, 90]
    private let checkEvery: TimeInterval = 30 * 60
    private let sweepEvery: TimeInterval = 24 * 60 * 60
    private var lastCheck = Date.distantPast
    private var sweeping = false
    private var trashedLastSweep = 0
    private var lastError: String?
    private let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/download-recycler.log")

    init(notifier: Notifier) { self.notifier = notifier }

    var enabled: Bool {
        get { defaults.object(forKey: "downloads.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "downloads.enabled"); onChange?() }
    }
    var daysToKeep: Int {
        get { let v = defaults.integer(forKey: "downloads.daysToKeep"); return Self.dayChoices.contains(v) ? v : 30 }
        set { defaults.set(newValue, forKey: "downloads.daysToKeep") }
    }
    var lastSweep: Date {
        get { defaults.object(forKey: "downloads.lastSweep") as? Date ?? .distantPast }
        set { defaults.set(newValue, forKey: "downloads.lastSweep") }
    }

    func tick(now: Date) {
        guard now.timeIntervalSince(lastCheck) >= checkEvery else { return }
        lastCheck = now
        if enabled && (lastError != nil || now.timeIntervalSince(lastSweep) >= sweepEvery) { sweep(manual: false) }
    }

    private func sweep(manual: Bool) {
        guard !sweeping else { return }
        sweeping = true
        let days = daysToKeep
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let downloads = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            var failure: String?
            var trashed = 0
            do {
                let urls = try fm.contentsOfDirectory(at: downloads, includingPropertiesForKeys: [.contentModificationDateKey],
                                                      options: [.skipsHiddenFiles])
                let items = urls.map { DownloadItem(url: $0, modified: (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) }
                for url in DownloadAge.expired(items, daysToKeep: days, now: Date()) {
                    do { try fm.trashItem(at: url, resultingItemURL: nil); trashed += 1; self.log("Trashed: \(url.lastPathComponent)") }
                    catch { self.log("FAILED to trash \(url.lastPathComponent): \(error.localizedDescription)") }
                }
            } catch {
                failure = "Needs access to Downloads"
                self.log("Could not read Downloads: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                self.sweeping = false
                self.lastError = failure
                guard failure == nil else { return }
                self.lastSweep = Date()
                self.trashedLastSweep = trashed
                self.log("Sweep done (threshold \(days)d): \(trashed) item(s) trashed")
                if trashed > 0 || manual {
                    self.notifier.post(title: "Mac Daddy", body: "Moved \(trashed) old item(s) from Downloads to the Trash.")
                }
                if trashed > 0 { self.onSweep?(.chainGlint) }
            }
        }
    }

    private func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: logURL) }
    }

    func addMenuItems(to menu: NSMenu) {
        heading("Downloads", error: lastError).forEach(menu.addItem)
        if lastError != nil, let errItem = menu.items.last {
            errItem.action = #selector(openPrivacy); errItem.target = self   // clicking the ⚠ line opens Files and Folders
        }
        let toggle = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self; toggle.state = enabled ? .on : .off
        menu.addItem(indented(toggle))
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        let last = lastSweep == .distantPast ? "never" : f.string(from: lastSweep)
        let run = NSMenuItem(title: "Sweep Now (last: \(last), \(trashedLastSweep) trashed)", action: #selector(runNow), keyEquivalent: "")
        run.target = self
        menu.addItem(indented(run))
        let keep = NSMenuItem(title: "Keep Files For", action: nil, keyEquivalent: "")
        let km = NSMenu()
        for d in Self.dayChoices {
            let i = NSMenuItem(title: "\(d) days", action: #selector(setDays(_:)), keyEquivalent: "")
            i.target = self; i.tag = d; i.state = d == daysToKeep ? .on : .off
            km.addItem(i)
        }
        keep.submenu = km
        menu.addItem(indented(keep))
        let log = NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "")
        log.target = self
        menu.addItem(indented(log))
    }

    @objc private func toggleEnabled() { enabled.toggle() }
    @objc private func runNow() { sweep(manual: true) }
    @objc private func setDays(_ s: NSMenuItem) { daysToKeep = s.tag }
    @objc private func openLog() { NSWorkspace.shared.open(logURL) }
    @objc private func openPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
    }
}
