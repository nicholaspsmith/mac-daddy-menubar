// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import AppKit
import LauncherCore
import SwiftUI

final class AliasesModel: ObservableObject {
    let store: EmojiStore
    let aliasStore: AliasStore
    let usage: UsageStore
    @Published var search = ""
    @Published var group: String? = nil
    @Published var onlyWithAliases = false
    @Published var onlyRecent = false
    @Published var sortOrder = [KeyPathComparator(\AliasRow.name)]
    @Published var saveError: String?

    init(store: EmojiStore, aliasStore: AliasStore, usage: UsageStore) {
        self.store = store; self.aliasStore = aliasStore; self.usage = usage
    }

    var rows: [AliasRow] {
        let r = AliasTable.rows(store: store, aliases: aliasStore.aliases, recents: usage.recentEmoji,
                                search: search, group: group, onlyWithAliases: onlyWithAliases, onlyRecent: onlyRecent)
        return search.isEmpty ? r.sorted(using: sortOrder) : r   // a search keeps its ranking
    }

    func setAliases(_ text: String, for char: String) {
        do {
            try aliasStore.setAliases(text.split(separator: ",").map(String.init), for: char)
            saveError = nil
        } catch {
            saveError = "aliases.json can't be read, so it isn't being changed. Fix or delete it first."
        }
        objectWillChange.send()
    }
}

struct AliasesView: View {
    @ObservedObject var model: AliasesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let err = model.aliasStore.loadError ?? model.saveError {
                Text(err).foregroundStyle(.red).font(.callout)
            }
            HStack {
                TextField("Search emoji", text: $model.search).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Picker("Category", selection: $model.group) {
                    Text("All").tag(String?.none)
                    ForEach(model.store.groups, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .frame(maxWidth: 240)
                Toggle("Has aliases", isOn: $model.onlyWithAliases)
                Toggle("Recently used", isOn: $model.onlyRecent)
            }
            Table(model.rows, sortOrder: $model.sortOrder) {
                TableColumn("Emoji", value: \.char) { Text($0.char).font(.system(size: 20)) }.width(50)
                TableColumn("Name", value: \.name)
                TableColumn("Category", value: \.group).width(150)
                TableColumn("Aliases", value: \.aliasText) { row in
                    AliasCell(text: row.aliasText) { model.setAliases($0, for: row.char) }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 760, minHeight: 480)
    }
}

/// Edits in place; saves on Return, or when focus leaves after a change.
struct AliasCell: View {
    @State var text: String
    @FocusState private var focused: Bool
    /// The value last saved (or loaded), so losing focus without an edit doesn't re-save.
    private let original: String
    let commit: (String) -> Void
    init(text: String, commit: @escaping (String) -> Void) {
        _text = State(initialValue: text)
        original = text
        self.commit = commit
    }
    var body: some View {
        TextField("add names, comma-separated", text: $text)
            .focused($focused)
            .onSubmit { commit(text) }
            .onChange(of: focused) { isFocused in
                if !isFocused, text != original { commit(text) }
            }
    }
}

final class AliasesWindowController {
    private var window: NSWindow?
    private let model: AliasesModel
    init(model: AliasesModel) { self.model = model }

    func show() {
        if window == nil {
            let w = EscClosableWindow(contentViewController: NSHostingController(rootView: AliasesView(model: model)))
            w.title = "Emoji Aliases"
            w.setContentSize(NSSize(width: 820, height: 560))
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
