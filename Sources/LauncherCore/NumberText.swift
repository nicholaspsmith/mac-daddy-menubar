// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation

public enum NumberText {
    private static let shape = try! NSRegularExpression(pattern: #"^(\d{1,3}(,\d{3})+|\d*)(\.\d*)?$"#)

    /// "12", ".5", "3.", "1,000.25" → value. Commas only as thousands separators.
    public static func value(of text: String) -> Double? {
        guard !text.isEmpty, text != ".",
              shape.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        else { return nil }
        return Double(text.replacingOccurrences(of: ",", with: ""))
    }

    /// Calculator answers: exact to 10 decimal places, no grouping, no trailing zeros.
    public static func answer(_ v: Double) -> String {
        format(v) { $0.maximumFractionDigits = 10 }
    }

    /// Conversion results: at most `digits` significant figures.
    public static func significant(_ v: Double, digits: Int = 6) -> String {
        format(v) { $0.usesSignificantDigits = true; $0.maximumSignificantDigits = digits }
    }

    private static func format(_ v: Double, _ configure: (NumberFormatter) -> Void) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        configure(f)
        let s = f.string(from: NSNumber(value: v)) ?? String(v)
        return s == "-0" ? "0" : s
    }
}
