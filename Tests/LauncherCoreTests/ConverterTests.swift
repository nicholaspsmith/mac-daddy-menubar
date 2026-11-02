// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import LauncherCore

final class ConverterTests: XCTestCase {
    let us = Converter(system: .usImperial)
    let metric = Converter(system: .metric)

    func assertConverts(_ input: String, _ bare: String, _ to: String, using c: Converter? = nil,
                        file: StaticString = #filePath, line: UInt = #line) {
        let r = (c ?? us).convert(input)
        XCTAssertEqual(r?.bare, bare, input, file: file, line: line)
        XCTAssertEqual(r?.to, to, input, file: file, line: line)
    }

    func testExplicitTargets() {
        assertConverts("72f to c", "22.2222", "°C")
        assertConverts("1 lb to kg", "0.453592", "kg")
        assertConverts("12 fl oz in pt", "0.75", "pt")
        assertConverts("2 pt to fl oz", "32", "fl oz")
        assertConverts("1 cup to ml", "236.588", "mL")
        assertConverts("5 in in cm", "12.7", "cm")
        assertConverts("1,000 ft to m", "304.8", "m")
        assertConverts("30 fps to m/s", "9.144", "m/s")
        assertConverts("32 ft/s2 to m/s²", "9.7536", "m/s²")
        assertConverts("9.80665 m/s^2 to g-force", "1", "g-force")
        assertConverts("60 mph as km/h", "96.5606", "km/h")
    }

    func testLooseTyping() {
        assertConverts("-40f to c", "-40", "°C")
        assertConverts("72F", "22.2222", "°C")
        assertConverts("5 KG TO LB", "11.0231", "lb")
        assertConverts("12 fl. oz in pt", "0.75", "pt")
        assertConverts("  72 °F  ", "22.2222", "°C")
        assertConverts("100 degrees f to c", "37.7778", "°C")
    }

    func testBareValuesFollowTheUnitSystem() {
        assertConverts("100 km/h", "62.1371", "mph")               // metric → US in US Imperial
        XCTAssertNil(metric.convert("100 km/h"))                    // metric stays put in Metric
        assertConverts("100 mph", "160.934", "km/h", using: metric) // US → metric in Metric
        assertConverts("72f", "22.2222", "°C", using: metric)
        assertConverts("10 knots", "11.5078", "mph")                // neutral → US in US Imperial
        assertConverts("10 knots", "18.52", "km/h", using: metric)  // neutral → metric in Metric
        assertConverts("5 in", "12.7", "cm")
    }

    func testExplicitTargetWinsOverSystem() {
        assertConverts("100 km/h to m/s", "27.7778", "m/s", using: metric)
    }

    func testNothingForNonsense() {
        XCTAssertNil(us.convert("5 kg to mph"))     // mismatched dimensions
        XCTAssertNil(us.convert("5 bananas"))
        XCTAssertNil(us.convert("5"))
        XCTAssertNil(us.convert("to c"))
        XCTAssertNil(us.convert("5 kg to kg"))
        XCTAssertNil(us.convert("safari"))
        XCTAssertNil(us.convert("5 kg to parsecs"))
    }

    func testDisplayStrings() {
        let r = us.convert("72f to c")!
        XCTAssertEqual(r.withUnit, "22.2222 °C")
        XCTAssertEqual(r.inputText, "72 °F")
        XCTAssertEqual(UnitSystem.usImperial.title, "US Imperial")
        XCTAssertEqual(UnitSystem.metric.title, "Metric")
    }
}
