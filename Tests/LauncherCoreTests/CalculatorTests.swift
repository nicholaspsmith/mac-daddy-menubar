// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import LauncherCore

final class CalculatorTests: XCTestCase {
    func e(_ s: String) -> Double? { Calculator.evaluate(s) }

    func testArithmeticAndPrecedence() {
        XCTAssertEqual(e("2+2"), 4)
        XCTAssertEqual(e("2 + 3 * 4"), 14)
        XCTAssertEqual(e("(2+3)*4"), 20)
        XCTAssertEqual(e("10/4"), 2.5)
        XCTAssertEqual(e("10 - 2 - 3"), 5)
        XCTAssertEqual(e("-5+2"), -3)
        XCTAssertEqual(e("3 x 4"), 12)
        XCTAssertEqual(e("3X4"), 12)
        XCTAssertEqual(e("2*-3"), -6)
    }

    func testNumberShapes() {
        XCTAssertEqual(e(".5*2"), 1)
        XCTAssertEqual(e("3.*2"), 6)
        XCTAssertEqual(e("1,000 * 2"), 2000)
        XCTAssertEqual(e("1,234.5 + 0.5"), 1235)
        XCTAssertNil(e("1,00*2"))
    }

    func testIncompleteInputGivesNothing() {
        XCTAssertNil(e("5+"))
        XCTAssertNil(e("2(3)"))
        XCTAssertNil(e("(2+3"))
        XCTAssertNil(e("*2"))
    }

    func testNotMathGivesNothing() {
        XCTAssertNil(e("42"))            // a lone number is not a calculation
        XCTAssertNil(e("-42"))
        XCTAssertNil(e("xcode"))
        XCTAssertNil(e("safari"))
        XCTAssertNil(e(""))
        XCTAssertNil(e("2 × 3"))         // only + - * / x are operators
    }

    func testDivisionByZeroAndOverflowGiveNothing() {
        XCTAssertNil(e("5/0"))
        XCTAssertNil(e("5/(2-2)"))
        let big = String(repeating: "9", count: 200)
        XCTAssertNil(e("\(big)*\(big)"))
    }

    func testFormatting() {
        XCTAssertEqual(NumberText.answer(0.1 + 0.2), "0.3")
        XCTAssertEqual(NumberText.answer(2.5), "2.5")
        XCTAssertEqual(NumberText.answer(-0.0), "0")
        XCTAssertEqual(NumberText.answer(1234567), "1234567")
        XCTAssertEqual(NumberText.significant(22.2222222), "22.2222")
        XCTAssertEqual(NumberText.significant(0.453592374), "0.453592")
        XCTAssertEqual(NumberText.significant(-40), "-40")
    }
}
