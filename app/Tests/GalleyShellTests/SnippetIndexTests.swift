//
//  SnippetIndexTests.swift
//  GalleyShellTests
//
//  Behavioral tests for `SnippetIndex`, derived from its Behavior Statements. The
//  `load` path runs against real `.txt` files on disk — no stub stands in for the
//  filesystem read (Integration Reality, rule 13a, ADR-0020).
//

import Foundation
import Testing
@testable import GalleyShell

@Suite("Snippet index loading and lookup")
struct SnippetIndexTests {

    @Test func matchesEmptyQueryReturnsAllSnippetsAlphabetically() {
        let index = SnippetIndex(entries: [
            Snippet(name: "Dateline", body: "LONDON —"),
            Snippet(name: "Chapter Epigraph", body: "\"...\""),
        ])
        #expect(index.matches(for: "").map(\.name) == ["Chapter Epigraph", "Dateline"])
    }

    @Test func matchesRanksBestFuzzyMatchFirst() {
        let index = SnippetIndex(entries: [
            Snippet(name: "Dateline", body: "LONDON —"),
            Snippet(name: "Chapter Epigraph", body: "\"...\""),
        ])
        #expect(index.matches(for: "date").first?.name == "Dateline")
    }

    @Test func matchesReturnsEmptyWhenNothingMatches() {
        let index = SnippetIndex(entries: [Snippet(name: "Dateline", body: "x")])
        #expect(index.matches(for: "zzzz").isEmpty)
    }

    @Test func snippetNamedIsCaseInsensitive() {
        let index = SnippetIndex(entries: [Snippet(name: "Dateline", body: "LONDON —")])
        #expect(index.snippet(named: "dateline")?.body == "LONDON —")
        #expect(index.snippet(named: "nope") == nil)
    }

    // MARK: load (real-path — directory of .txt files)

    @Test func loadParsesEveryTextFileNamingFromFilenameAndKeepingBody() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Trailing newline (as editors append) is trimmed; interior blank lines kept.
        try "First line.\n\nSecond paragraph.\n".write(
            to: dir.appendingPathComponent("chapter-epigraph.txt"), atomically: true, encoding: .utf8)
        try "LONDON —".write(
            to: dir.appendingPathComponent("dateline.txt"), atomically: true, encoding: .utf8)
        // A non-txt file must be ignored.
        try "ignore".write(
            to: dir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

        let index = SnippetIndex.load(directory: dir)

        #expect(index.entries.count == 2)
        #expect(index.snippet(named: "Dateline")?.body == "LONDON —")
        #expect(index.snippet(named: "Chapter Epigraph")?.body == "First line.\n\nSecond paragraph.")
    }

    @Test func loadMissingDirectoryYieldsEmptyIndex() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(SnippetIndex.load(directory: missing).entries.isEmpty)
    }
}
