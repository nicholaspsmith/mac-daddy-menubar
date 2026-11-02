// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation

public enum SkinTone: Int, CaseIterable, Codable, Sendable {
    case none = 0, light, mediumLight, medium, mediumDark, dark

    public var title: String {
        ["Default", "Light", "Medium-Light", "Medium", "Medium-Dark", "Dark"][rawValue]
    }
    public var swatch: String { ["✋", "✋🏻", "✋🏼", "✋🏽", "✋🏾", "✋🏿"][rawValue] }
    public var next: SkinTone { SkinTone(rawValue: (rawValue + 1) % SkinTone.allCases.count)! }
}

public struct Emoji: Codable, Equatable, Sendable {
    public let char: String
    public let name: String
    public let keywords: [String]
    public let group: String
    /// Light → dark variants, for emoji that take a skin tone.
    public let tones: [String]?

    enum CodingKeys: String, CodingKey {
        case char = "c", name = "n", keywords = "k", group = "g", tones = "t"
    }

    public func glyph(_ tone: SkinTone) -> String {
        guard tone != .none, let tones, tones.count == 5 else { return char }
        return tones[tone.rawValue - 1]
    }
}

public struct EmojiHit: Equatable, Identifiable, Sendable {
    public let emoji: Emoji
    public let score: Double
    public var id: String { emoji.char }
}
