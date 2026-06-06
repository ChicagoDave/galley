//
//  TypographyTests.swift
//  UntitledCoreTests
//
//  Behavioral tests for `smartTypography` (§8): curly quotes by context, em dash
//  from a double hyphen, ellipsis from a triple dot. Each asserts the exact
//  `TypographyEdit` (what to delete + insert).
//

import Testing
@testable import UntitledCore

@Suite("smartTypography")
struct TypographyTests {

    @Test func doubleQuoteOpensAtStartOfBlock() {
        #expect(smartTypography(inserting: "\"", precededBy: (nil, nil))
            == TypographyEdit(deletePreceding: 0, text: "\u{201C}"))
    }

    @Test func doubleQuoteOpensAfterSpace() {
        #expect(smartTypography(inserting: "\"", precededBy: ("d", " "))
            == TypographyEdit(deletePreceding: 0, text: "\u{201C}"))
    }

    @Test func doubleQuoteClosesAfterLetter() {
        #expect(smartTypography(inserting: "\"", precededBy: ("a", "y"))
            == TypographyEdit(deletePreceding: 0, text: "\u{201D}"))
    }

    @Test func apostropheClosesAfterLetter() {
        #expect(smartTypography(inserting: "'", precededBy: ("n", "t"))
            == TypographyEdit(deletePreceding: 0, text: "\u{2019}"))
    }

    @Test func secondHyphenBecomesEmDashDeletingTheFirst() {
        #expect(smartTypography(inserting: "-", precededBy: ("o", "-"))
            == TypographyEdit(deletePreceding: 1, text: "\u{2014}"))
    }

    @Test func thirdDotBecomesEllipsisDeletingTwo() {
        #expect(smartTypography(inserting: ".", precededBy: (".", "."))
            == TypographyEdit(deletePreceding: 2, text: "\u{2026}"))
    }

    @Test func ordinaryCharacterPassesThrough() {
        #expect(smartTypography(inserting: "a", precededBy: ("b", "c"))
            == TypographyEdit(deletePreceding: 0, text: "a"))
    }

    @Test func pastedFragmentCollapsesLiteralEllipsis() {
        #expect(smartTypography(inserting: "wait...", precededBy: (nil, nil))
            == TypographyEdit(deletePreceding: 0, text: "wait\u{2026}"))
    }
}
