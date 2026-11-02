// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation

public enum UnitSystem: String, CaseIterable, Sendable {
    case usImperial, metric
    public var title: String { self == .usImperial ? "US Imperial" : "Metric" }
}

enum UnitFamily: Sendable { case us, metric, neutral }

struct UnitDef {
    let symbol: String
    let unit: Dimension
    let family: UnitFamily
    let aliases: [String]        // already normalized (see UnitCatalog.normalize)
    let usPartner: String?       // symbol suggested for a bare value
    let metricPartner: String?
}

enum UnitCatalog {
    /// Lowercase, fold, drop spaces and periods, "²"/"^2" → "2".
    static func normalize(_ s: String) -> String {
        Query.fold(s)
            .replacingOccurrences(of: "²", with: "2")
            .replacingOccurrences(of: "^", with: "")
            .filter { !$0.isWhitespace && $0 != "." }
    }

    // US customary cup (236.588 mL); Foundation's .cups is the 240 mL metric cup.
    static let usCup = UnitVolume(symbol: "cup", converter: UnitConverterLinear(coefficient: 0.2365882365))
    static let feetPerSecond = UnitSpeed(symbol: "ft/s", converter: UnitConverterLinear(coefficient: 0.3048))
    static let feetPerSecondSquared = UnitAcceleration(symbol: "ft/s²", converter: UnitConverterLinear(coefficient: 0.3048))
    // Precise km/h (Foundation uses rounded 0.277778); 1 km/h = 1000 m / 3600 s = 0.27777... m/s
    static let kilometersPerHour = UnitSpeed(symbol: "km/h", converter: UnitConverterLinear(coefficient: 1000.0 / 3600.0))
    // Standard gravity: 9.80665 m/s² (Foundation uses 9.81)
    static let standardGravity = UnitAcceleration(symbol: "g-force", converter: UnitConverterLinear(coefficient: 9.80665))

    static let all: [UnitDef] = [
        // Temperature
        UnitDef(symbol: "°F", unit: UnitTemperature.fahrenheit, family: .us,
                aliases: ["f", "°f", "fahrenheit", "degf", "degreesf", "degreesfahrenheit"], usPartner: nil, metricPartner: "°C"),
        UnitDef(symbol: "°C", unit: UnitTemperature.celsius, family: .metric,
                aliases: ["c", "°c", "celsius", "centigrade", "degc", "degreesc", "degreescelsius"], usPartner: "°F", metricPartner: nil),
        UnitDef(symbol: "K", unit: UnitTemperature.kelvin, family: .neutral,
                aliases: ["k", "kelvin", "kelvins"], usPartner: "°F", metricPartner: "°C"),
        // Mass
        UnitDef(symbol: "lb", unit: UnitMass.pounds, family: .us,
                aliases: ["lb", "lbs", "pound", "pounds"], usPartner: nil, metricPartner: "kg"),
        UnitDef(symbol: "oz", unit: UnitMass.ounces, family: .us,
                aliases: ["oz", "ounce", "ounces"], usPartner: nil, metricPartner: "g"),
        UnitDef(symbol: "st", unit: UnitMass.stones, family: .us,
                aliases: ["st", "stone", "stones"], usPartner: nil, metricPartner: "kg"),
        UnitDef(symbol: "kg", unit: UnitMass.kilograms, family: .metric,
                aliases: ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"], usPartner: "lb", metricPartner: nil),
        UnitDef(symbol: "g", unit: UnitMass.grams, family: .metric,
                aliases: ["g", "gram", "grams"], usPartner: "oz", metricPartner: nil),
        // Volume
        UnitDef(symbol: "fl oz", unit: UnitVolume.fluidOunces, family: .us,
                aliases: ["floz", "fluidounce", "fluidounces"], usPartner: nil, metricPartner: "mL"),
        UnitDef(symbol: "cup", unit: usCup, family: .us,
                aliases: ["cup", "cups"], usPartner: nil, metricPartner: "mL"),
        UnitDef(symbol: "pt", unit: UnitVolume.pints, family: .us,
                aliases: ["pt", "pint", "pints"], usPartner: nil, metricPartner: "mL"),
        UnitDef(symbol: "qt", unit: UnitVolume.quarts, family: .us,
                aliases: ["qt", "quart", "quarts"], usPartner: nil, metricPartner: "L"),
        UnitDef(symbol: "gal", unit: UnitVolume.gallons, family: .us,
                aliases: ["gal", "gals", "gallon", "gallons"], usPartner: nil, metricPartner: "L"),
        UnitDef(symbol: "tsp", unit: UnitVolume.teaspoons, family: .us,
                aliases: ["tsp", "teaspoon", "teaspoons"], usPartner: nil, metricPartner: "mL"),
        UnitDef(symbol: "tbsp", unit: UnitVolume.tablespoons, family: .us,
                aliases: ["tbsp", "tbs", "tablespoon", "tablespoons"], usPartner: nil, metricPartner: "mL"),
        UnitDef(symbol: "mL", unit: UnitVolume.milliliters, family: .metric,
                aliases: ["ml", "milliliter", "milliliters", "millilitre", "millilitres"], usPartner: "fl oz", metricPartner: nil),
        UnitDef(symbol: "L", unit: UnitVolume.liters, family: .metric,
                aliases: ["l", "liter", "liters", "litre", "litres"], usPartner: "qt", metricPartner: nil),
        // Length
        UnitDef(symbol: "in", unit: UnitLength.inches, family: .us,
                aliases: ["in", "inch", "inches"], usPartner: nil, metricPartner: "cm"),
        UnitDef(symbol: "ft", unit: UnitLength.feet, family: .us,
                aliases: ["ft", "foot", "feet"], usPartner: nil, metricPartner: "m"),
        UnitDef(symbol: "yd", unit: UnitLength.yards, family: .us,
                aliases: ["yd", "yds", "yard", "yards"], usPartner: nil, metricPartner: "m"),
        UnitDef(symbol: "mi", unit: UnitLength.miles, family: .us,
                aliases: ["mi", "mile", "miles"], usPartner: nil, metricPartner: "km"),
        UnitDef(symbol: "mm", unit: UnitLength.millimeters, family: .metric,
                aliases: ["mm", "millimeter", "millimeters", "millimetre", "millimetres"], usPartner: "in", metricPartner: nil),
        UnitDef(symbol: "cm", unit: UnitLength.centimeters, family: .metric,
                aliases: ["cm", "centimeter", "centimeters", "centimetre", "centimetres"], usPartner: "in", metricPartner: nil),
        UnitDef(symbol: "m", unit: UnitLength.meters, family: .metric,
                aliases: ["m", "meter", "meters", "metre", "metres"], usPartner: "ft", metricPartner: nil),
        UnitDef(symbol: "km", unit: UnitLength.kilometers, family: .metric,
                aliases: ["km", "kms", "kilometer", "kilometers", "kilometre", "kilometres"], usPartner: "mi", metricPartner: nil),
        // Speed
        UnitDef(symbol: "mph", unit: UnitSpeed.milesPerHour, family: .us,
                aliases: ["mph", "mi/h", "milesperhour"], usPartner: nil, metricPartner: "km/h"),
        UnitDef(symbol: "ft/s", unit: feetPerSecond, family: .us,
                aliases: ["ft/s", "fps", "feetpersecond", "footpersecond"], usPartner: nil, metricPartner: "m/s"),
        UnitDef(symbol: "km/h", unit: kilometersPerHour, family: .metric,
                aliases: ["km/h", "kmh", "kph", "kmph", "kilometersperhour", "kilometresperhour"], usPartner: "mph", metricPartner: nil),
        UnitDef(symbol: "m/s", unit: UnitSpeed.metersPerSecond, family: .metric,
                aliases: ["m/s", "mps", "meterspersecond", "metrespersecond"], usPartner: "mph", metricPartner: nil),
        UnitDef(symbol: "kn", unit: UnitSpeed.knots, family: .neutral,
                aliases: ["kn", "kt", "kts", "knot", "knots"], usPartner: "mph", metricPartner: "km/h"),
        // Acceleration
        UnitDef(symbol: "m/s²", unit: UnitAcceleration.metersPerSecondSquared, family: .metric,
                aliases: ["m/s2", "mps2", "meterspersecondsquared", "metrespersecondsquared"], usPartner: "ft/s²", metricPartner: nil),
        UnitDef(symbol: "ft/s²", unit: feetPerSecondSquared, family: .us,
                aliases: ["ft/s2", "fps2", "feetpersecondsquared"], usPartner: nil, metricPartner: "m/s²"),
        UnitDef(symbol: "g-force", unit: standardGravity, family: .neutral,
                aliases: ["g-force", "gforce", "gs", "gee", "gees", "standardgravity"], usPartner: "ft/s²", metricPartner: "m/s²"),
    ]

    static let byAlias: [String: UnitDef] = {
        var map: [String: UnitDef] = [:]
        for def in all { for a in def.aliases { map[a] = def } }
        return map
    }()

    static let bySymbol: [String: UnitDef] = Dictionary(uniqueKeysWithValues: all.map { ($0.symbol, $0) })

    static func lookup(_ text: String) -> UnitDef? {
        let n = normalize(text)
        return byAlias[n] ?? bySymbol.values.first { normalize($0.symbol) == n }
    }
}
