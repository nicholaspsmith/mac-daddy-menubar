// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import LauncherCore

final class MatcherTests: XCTestCase {
    func s(_ q: String, _ fields: String...) -> Double? { Matcher.score(Query(q), MatchTarget(fields)) }

    func testPrefixBeatsAcronymBeatsSubsequence() {
        let prefix = s("vis", "Visual Studio Code")!
        let acronym = s("vsc", "Visual Studio Code")!
        let subsequence = s("vsd", "Visual Studio Code")!
        XCTAssertGreaterThan(prefix, acronym)
        XCTAssertGreaterThan(acronym, subsequence)
        XCTAssertEqual(acronym, Matcher.acronymScore)
        XCTAssertEqual(subsequence, Matcher.subsequenceScore)
    }

    func testWordOrderDoesNotMatter() {
        XCTAssertNotNil(s("crossed fingers", "crossed fingers"))
        XCTAssertNotNil(s("fingers crossed", "crossed fingers"))
        XCTAssertNotNil(s("cross fing", "crossed fingers"))
    }

    func testEveryWordMustMatch() {
        XCTAssertNil(s("crossed banana", "crossed fingers"))
        XCTAssertNil(s("zzz", "Safari"))
    }

    func testCaseDiacriticsAndWhitespaceAreIgnored() {
        XCTAssertNotNil(s("  SAFARI ", "Safari"))
        XCTAssertNotNil(s("cafe", "Café Menu"))
        XCTAssertNotNil(s("CAFÉ", "cafe menu"))
    }

    func testFirstWordStartMatchRanksHigher() {
        XCTAssertGreaterThan(s("saf", "Safari")!, s("saf", "Open Safari")!)
    }

    func testExactWordBeatsLongerWord() {
        XCTAssertGreaterThan(s("mail", "Mail")!, s("mail", "Mailplane")!)
    }

    func testEmptyQueryMatchesNothing() {
        XCTAssertNil(s("", "Safari"))
        XCTAssertNil(s("   ", "Safari"))
    }

    func testPurelyNonAlphanumericQueryMatchesNothing() {
        XCTAssertNil(s("???", "Safari"))
        XCTAssertNil(s("-- !!", "Safari"))
    }

    func testPunctuationMixedWithRealWordStillMatches() {
        XCTAssertNotNil(s("saf !", "Safari"))
    }
}
