// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation

public struct Conversion: Equatable, Sendable {
    public let input: Double
    public let from: String
    public let to: String
    public let result: Double

    public var bare: String { NumberText.significant(result) }
    public var withUnit: String { "\(bare) \(to)" }
    public var inputText: String { "\(NumberText.significant(input)) \(from)" }
}

public struct Converter: Sendable {
    public let system: UnitSystem
    public init(system: UnitSystem) { self.system = system }

    private static let leadingNumber = try! NSRegularExpression(pattern: #"^([+-]?[\d.,]+)\s*(.+)$"#)
    private static let withTarget = try! NSRegularExpression(
        pattern: #"^(.+?)\s+(?:to|in|into|as|->|→)\s+(.+)$"#)

    public func convert(_ input: String) -> Conversion? {
        let s = Query.fold(input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = Self.leadingNumber.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let numRange = Range(m.range(at: 1), in: s), let restRange = Range(m.range(at: 2), in: s)
        else { return nil }
        var numText = String(s[numRange])
        let negative = numText.hasPrefix("-")
        if numText.hasPrefix("-") || numText.hasPrefix("+") { numText.removeFirst() }
        guard var value = NumberText.value(of: numText) else { return nil }
        if negative { value = -value }

        let rest = String(s[restRange])
        let fromDef: UnitDef, toDef: UnitDef
        if let t = Self.withTarget.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
           let a = Range(t.range(at: 1), in: rest), let b = Range(t.range(at: 2), in: rest),
           let f = UnitCatalog.lookup(String(rest[a])) {
            guard let target = UnitCatalog.lookup(String(rest[b])) else { return nil }
            fromDef = f; toDef = target
        } else {
            guard let f = UnitCatalog.lookup(rest), let p = partner(for: f) else { return nil }
            fromDef = f; toDef = p
        }
        guard fromDef.symbol != toDef.symbol,
              type(of: fromDef.unit).baseUnit().symbol == type(of: toDef.unit).baseUnit().symbol else { return nil }
        let base = fromDef.unit.converter.baseUnitValue(fromValue: value)
        let result = toDef.unit.converter.value(fromBaseUnitValue: base)
        guard result.isFinite else { return nil }
        return Conversion(input: value, from: fromDef.symbol, to: toDef.symbol, result: result)
    }

    /// Where a bare value goes: US units convert to metric; metric units to US in US Imperial
    /// and nowhere in Metric; neutral units (K, knots, g-force) to the chosen system.
    func partner(for d: UnitDef) -> UnitDef? {
        let symbol: String?
        switch (d.family, system) {
        case (.us, _): symbol = d.metricPartner
        case (.metric, .usImperial): symbol = d.usPartner
        case (.metric, .metric): symbol = nil
        case (.neutral, .usImperial): symbol = d.usPartner
        case (.neutral, .metric): symbol = d.metricPartner
        }
        return symbol.flatMap { UnitCatalog.bySymbol[$0] }
    }
}
