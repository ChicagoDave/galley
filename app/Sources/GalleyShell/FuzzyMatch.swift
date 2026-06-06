//
//  FuzzyMatch.swift
//  GalleyShell
//
//  Purpose: The shared, pure fuzzy-matching primitives used by the reference
//  surfaces (§9) — filename humanisation and a subsequence scorer. No AI, no
//  external dependency (ADR-0008); both the bible panel and `@`-snippet completion
//  rank candidates through these. Carries no AppKit, so it is headlessly testable.
//  Public interface: `FuzzyMatch.humanize(_:)`, `FuzzyMatch.score(query:in:)`.
//  Owner context: GalleyShell — app-layer reference utilities. Foundation only.
//

import Foundation

/// Pure fuzzy-matching helpers shared by `BibleIndex` and `SnippetIndex`.
public enum FuzzyMatch {

    /// Turns a filename stem into a display name: word-separates on `-`/`_`/space,
    /// then capitalises the first letter of each word, leaving the rest untouched so
    /// existing internal capitals (e.g. "McKay") survive.
    public static func humanize(_ stem: String) -> String {
        stem
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
            .map { word -> String in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    /// Scores how well `query` fuzzy-matches `candidate`, or `nil` if `query` is not
    /// a subsequence of `candidate` (case-insensitive).
    ///
    /// Higher is better. Rewards matches at the string start, at word boundaries
    /// (after a space or `-`), in contiguous streaks, and close together — so "af"
    /// ranks "Aldous Finch" above a scattered coincidental match.
    ///
    /// - Parameters:
    ///   - query: the search text.
    ///   - candidate: the string to score against.
    /// - Returns: the match score, or `nil` if not a subsequence. An empty query
    ///   scores `0` (matches everything).
    public static func score(query: String, in candidate: String) -> Int? {
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        guard !q.isEmpty else { return 0 }

        var qi = 0
        var score = 0
        var lastMatch = -2

        for (ci, ch) in c.enumerated() where qi < q.count && ch == q[qi] {
            if ci == 0 { score += 12 }
            if ci > 0, c[ci - 1] == " " || c[ci - 1] == "-" { score += 9 }
            if lastMatch == ci - 1 { score += 7 }                     // contiguous streak
            score += max(0, 4 - (ci - lastMatch - 1))                 // proximity
            lastMatch = ci
            qi += 1
        }

        return qi == q.count ? score : nil
    }
}
