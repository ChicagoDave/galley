//
//  BibleIndexTests.swift
//  GalleyShellTests
//
//  Behavioral tests for `BibleIndex`, derived from its Behavior Statements. The
//  pure helpers (parse, humanize, fuzzy score) are tested directly; `load` is
//  exercised against a real directory of `*.md` files on disk — no stub stands in
//  for the filesystem read (Integration Reality, rule 13a, ADR-0020).
//

import Foundation
import Testing
import GalleyCore
@testable import GalleyShell

@Suite("Bible index parsing and fuzzy lookup")
struct BibleIndexTests {

    // MARK: parseEntry / humanize

    @Test func humanizeFilenameStemTitleCasesWords() {
        #expect(FuzzyMatch.humanize("aldous-finch") == "Aldous Finch")
        #expect(FuzzyMatch.humanize("the_gray_harbor") == "The Gray Harbor")
    }

    @Test func humanizePreservesInternalCapitals() {
        #expect(FuzzyMatch.humanize("captain-mcKay") == "Captain McKay")
    }

    @Test func parseEntryDerivesNameFromFilenameWhenNoHeading() {
        let entry = BibleIndex.parseEntry(filename: "gray-harbor.md", content: "A cold port town.")
        #expect(entry.name == "Gray Harbor")
        #expect(entry.canonicalText == "Gray Harbor")
        #expect(entry.notes == "A cold port town.")
    }

    @Test func parseEntryUsesLeadingHeadingAsNameAndStripsItFromNotes() {
        let content = "# Aldous Finch\n\nGruff harbormaster. Limps."
        let entry = BibleIndex.parseEntry(filename: "aldous-finch.md", content: content)
        #expect(entry.name == "Aldous Finch")
        #expect(entry.canonicalText == "Aldous Finch")
        #expect(entry.notes == "Gruff harbormaster. Limps.")
    }

    // MARK: fuzzyScore

    @Test func fuzzyScoreReturnsNilForNonSubsequence() {
        #expect(FuzzyMatch.score(query: "xyz", in: "Aldous Finch") == nil)
    }

    @Test func fuzzyScoreMatchesSubsequenceCaseInsensitively() {
        #expect(FuzzyMatch.score(query: "af", in: "Aldous Finch") != nil)
    }

    @Test func fuzzyScoreRanksWordBoundaryInitialsAboveScatteredMatch() {
        // "af" as the two word-initials of "Aldous Finch" must beat the same letters
        // appearing scattered inside another name.
        let initials = FuzzyMatch.score(query: "af", in: "Aldous Finch")
        let scattered = FuzzyMatch.score(query: "af", in: "Rafael Stone")
        #expect(initials != nil)
        #expect(scattered != nil)
        #expect(initials! > scattered!)
    }

    // MARK: matches

    @Test func matchesEmptyQueryReturnsAllEntriesAlphabetically() {
        let index = BibleIndex(entries: [
            BibleEntry(name: "Gray Harbor", canonicalText: "Gray Harbor"),
            BibleEntry(name: "Aldous Finch", canonicalText: "Aldous Finch"),
        ])
        #expect(index.matches(for: "").map(\.name) == ["Aldous Finch", "Gray Harbor"])
    }

    @Test func matchesRanksBestFuzzyMatchFirst() {
        let index = BibleIndex(entries: [
            BibleEntry(name: "Gray Harbor", canonicalText: "Gray Harbor"),
            BibleEntry(name: "Aldous Finch", canonicalText: "Aldous Finch"),
        ])
        #expect(index.matches(for: "ald").first?.name == "Aldous Finch")
    }

    @Test func matchesReturnsEmptyWhenNothingMatches() {
        let index = BibleIndex(entries: [BibleEntry(name: "Aldous Finch", canonicalText: "Aldous Finch")])
        #expect(index.matches(for: "zzzz").isEmpty)
    }

    @Test func matchesRespectsLimit() {
        let index = BibleIndex(entries: (0..<20).map { BibleEntry(name: "Entry \($0)", canonicalText: "Entry \($0)") })
        #expect(index.matches(for: "", limit: 3).count == 3)
    }

    @Test func entryNamedIsCaseInsensitive() {
        let index = BibleIndex(entries: [BibleEntry(name: "Aldous Finch", canonicalText: "Aldous Finch")])
        #expect(index.entry(named: "aldous finch")?.name == "Aldous Finch")
        #expect(index.entry(named: "nobody") == nil)
    }

    // MARK: load (real-path — directory of .md files)

    @Test func loadParsesEveryMarkdownFileInDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "# Aldous Finch\nGruff harbormaster.".write(
            to: dir.appendingPathComponent("aldous-finch.md"), atomically: true, encoding: .utf8)
        try "A cold port town.".write(
            to: dir.appendingPathComponent("gray-harbor.md"), atomically: true, encoding: .utf8)
        // A non-markdown file must be ignored.
        try "ignore me".write(
            to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let index = BibleIndex.load(directory: dir)

        #expect(index.entries.count == 2)
        #expect(index.entry(named: "Aldous Finch")?.notes == "Gruff harbormaster.")
        #expect(index.entry(named: "Gray Harbor")?.notes == "A cold port town.")
    }

    @Test func loadMissingDirectoryYieldsEmptyIndex() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(BibleIndex.load(directory: missing).entries.isEmpty)
    }
}
