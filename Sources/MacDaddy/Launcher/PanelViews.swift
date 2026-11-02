// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import LauncherCore
import SwiftUI

enum PanelMetrics {
    static let width: CGFloat = PanelPlacement.panelWidth
    static let fieldHeight: CGFloat = 56
    static let rowHeight: CGFloat = 44
    static let footerHeight: CGFloat = 28
    static let maxRows = 8
    static let emojiBodyHeight: CGFloat = 360
}

struct PanelBody: View {
    @ObservedObject var state: PanelState
    @ObservedObject var ui: EmojiUI
    let icons: IconCache
    let onClick: (Int) -> Void
    let onBack: () -> Void
    let onPick: (EmojiHit) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if state.mode == .emoji {
                Divider()
                EmojiGridView(state: state, ui: ui, onBack: onBack, onPick: onPick)
            } else if !state.results.isEmpty {
                Divider()
                ResultListView(state: state, icons: icons, onClick: onClick)
            }
            FooterView(state: state)
        }
        .background(WindowDragArea())
    }
}

struct ResultListView: View {
    @ObservedObject var state: PanelState
    let icons: IconCache
    let onClick: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(state.results.enumerated()), id: \.element.id) { i, item in
                        ResultRow(item: item, index: i, selected: i == state.selection, icons: icons)
                            .contentShape(Rectangle())
                            .onTapGesture { onClick(i) }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: state.selection) { i in
                // Scroll by the row's own id: a separate `.id(i)` on each row fights the
                // ForEach identity and leaves LazyVStack showing rows from an earlier query.
                if i < state.results.count { proxy.scrollTo(state.results[i].id) }
            }
        }
    }
}

struct ResultRow: View {
    let item: ResultItem
    let index: Int
    let selected: Bool
    let icons: IconCache

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(item.kind == .answer ? .system(size: 20, weight: .semibold) : .system(size: 14))
                    .lineLimit(1)
                Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if index < 9 { Text("⌘\(index + 1)").font(.system(size: 11)).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 12)
        .frame(height: PanelMetrics.rowHeight)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.25) : .clear))
        .padding(.horizontal, 8)
    }

    @ViewBuilder var icon: some View {
        switch item.icon {
        case .app(let url): Image(nsImage: icons.icon(for: url)).resizable()
        case .emoji(let s): Text(s).font(.system(size: 22))
        case .symbol(let name): Image(systemName: name).font(.system(size: 20)).foregroundStyle(.secondary)
        }
    }
}

struct FooterView: View {
    @ObservedObject var state: PanelState

    var body: some View {
        HStack {
            Text(leftHint)
            Spacer()
            Text(state.footerMessage ?? hint)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: PanelMetrics.footerHeight)
    }

    /// ⌘↩ hands a typed query to Spotlight; with nothing typed, the settings hint.
    var leftHint: String {
        state.mode == .main && !state.query.trimmingCharacters(in: .whitespaces).isEmpty
            ? "⌘↩ Search in Spotlight" : "⌘, for settings"
    }

    var hint: String {
        switch state.mode {
        case .main: return state.selectedResult?.footerHint ?? ""
        case .emoji: return state.selectedEmoji == nil ? "" : "↩ Copy   ⌘K Aliases   ⌘⇧S Skin tone"
        }
    }
}
