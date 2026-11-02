// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import LauncherCore
import SwiftUI

/// UI-only emoji state: the alias editor and the current skin tone.
final class EmojiUI: ObservableObject {
    var onClose: (() -> Void)?
    @Published var editing: Emoji? {
        didSet {
            aliasError = nil
            if editing == nil { onClose?() }
        }
    }
    @Published var tone: SkinTone = LauncherPreferences.skinTone
    @Published var aliasError: String?
}

struct EmojiGridView: View {
    @ObservedObject var state: PanelState
    @ObservedObject var ui: EmojiUI
    let onBack: () -> Void
    let onPick: (EmojiHit) -> Void

    private var columns: [GridItem] { Array(repeating: GridItem(.fixed(64), spacing: 8), count: state.gridColumns) }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: onBack) { Text("‹ Back") }.buttonStyle(.borderless)
                Spacer()
                Text(state.selectedEmoji?.emoji.name.capitalized ?? "").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(state.emoji.enumerated()), id: \.element.id) { i, hit in
                            Text(hit.emoji.glyph(ui.tone))
                                .font(.system(size: 34))
                                .frame(width: 64, height: 52)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(i == state.selection ? Color.accentColor.opacity(0.3) : .clear))
                                .contentShape(Rectangle())
                                .onTapGesture { if ui.editing == nil { onPick(hit) } }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .onChange(of: state.selection) { i in
                    // Scroll by the cell's own id, as ResultListView does: a separate `.id(i)`
                    // fights the ForEach identity and leaves stale cells on screen.
                    if i < state.emoji.count { proxy.scrollTo(state.emoji[i].id) }
                }
                .onChange(of: state.query) { _ in
                    // A new search selects the first cell; bring it back into view even when the
                    // selection index didn't change (e.g. the grid was scrolled with the mouse).
                    if let first = state.emoji.first { proxy.scrollTo(first.id) }
                }
            }
        }
        .padding(.top, 6)
        .overlay { if let e = ui.editing { AliasEditorView(emoji: e, ui: ui) } }
    }
}

struct AliasEditorView: View {
    let emoji: Emoji
    @ObservedObject var ui: EmojiUI
    @State private var newAlias = ""
    @FocusState private var focused: Bool
    /// Set by the app: current aliases for an emoji, and a saver that throws when the file is unreadable.
    static var aliasesFor: (String) -> [String] = { _ in [] }
    static var save: ([String], String) throws -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(emoji.char).font(.system(size: 40)); Text(emoji.name.capitalized).font(.headline) }
            ForEach(Self.aliasesFor(emoji.char), id: \.self) { alias in
                HStack {
                    Text(alias)
                    Spacer()
                    Button("Remove") { update(Self.aliasesFor(emoji.char).filter { $0 != alias }) }
                        .buttonStyle(.borderless)
                }
            }
            TextField("Add a name, then Return", text: $newAlias)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit {
                    update(Self.aliasesFor(emoji.char) + [newAlias])
                    newAlias = ""
                }
            if let err = ui.aliasError { Text(err).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("Done") { ui.editing = nil } .keyboardShortcut(.cancelAction) }
        }
        .padding(16)
        .frame(width: 360)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .shadow(radius: 12)
        // Next runloop turn: on appear the search field still holds focus, and a same-turn
        // FocusState change is dropped, leaving typing in the search field.
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func update(_ names: [String]) {
        do { try Self.save(names, emoji.char); ui.aliasError = nil }
        catch { ui.aliasError = "aliases.json can't be read, so it isn't being changed. Fix or delete it first." }
        ui.objectWillChange.send()
    }
}
