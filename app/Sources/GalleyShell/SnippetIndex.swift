//
//  SnippetIndex.swift
//  GalleyShell
//
//  Purpose: The `@`-snippet source (§9) — a fuzzy index over the writer's reusable
//  text blocks, one `.txt` file per snippet, read from a `snippets/` directory
//  inside the `.galley` package. `@` lists snippets by name; choosing one inserts
//  its body verbatim into the prose. Loading is plain file I/O and matching is the
//  shared pure scorer (`FuzzyMatch`); there is no AI (ADR-0008). Lives in the app
//  layer (file I/O, ADR-0020); carries no AppKit, so it is headlessly testable.
//  Public interface: `Snippet`, `SnippetIndex`, `entries`, `load(directory:)`,
//  `matches(for:limit:)`, `snippet(named:)`.
//  Owner context: GalleyShell — app-layer reference service. Foundation only.
//

import Foundation

/// One reusable text block: a name (for the `@` menu) and the body inserted into
/// the prose when chosen.
public struct Snippet: Equatable, Hashable, Sendable {

    /// The snippet's display name / lookup key, derived from its filename.
    public var name: String

    /// The text inserted verbatim when the snippet is chosen.
    public var body: String

    /// Creates a snippet.
    public init(name: String, body: String) {
        self.name = name
        self.body = body
    }
}

/// A fuzzy index over a project's reusable text snippets (§9).
///
/// Each snippet is one `*.txt` file in the package's `snippets/` directory; the name
/// is derived from the filename (`chapter-epigraph.txt` → "Chapter Epigraph") and
/// the body is the file's contents.
public struct SnippetIndex: Equatable, Sendable {

    /// The indexed snippets, in load order (one per file).
    public private(set) var entries: [Snippet]

    /// Creates an index over an explicit set of snippets. The `load(directory:)`
    /// factory is the normal entry point; this exists for composition and testing.
    public init(entries: [Snippet] = []) {
        self.entries = entries
    }

    /// Loads a snippet index from a directory of `*.txt` files.
    ///
    /// Every `.txt` file becomes one snippet. A missing or unreadable directory
    /// yields an empty index — a project without snippets is normal (ADR-0008).
    ///
    /// - Parameter directory: the package's `snippets/` directory URL.
    /// - Returns: an index over the directory's snippets, or an empty index.
    public static func load(directory: URL) -> SnippetIndex {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        let entries = files
            .filter { $0.pathExtension.lowercased() == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url -> Snippet? in
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let name = FuzzyMatch.humanize((url.lastPathComponent as NSString).deletingPathExtension)
                // Trim only the trailing newline most editors append; keep interior
                // blank lines so multi-paragraph snippets survive intact.
                let body = content.hasSuffix("\n") ? String(content.dropLast()) : content
                return Snippet(name: name, body: body)
            }

        return SnippetIndex(entries: entries)
    }

    /// The snippets whose name fuzzy-matches `query`, ranked best-first.
    ///
    /// An empty query returns every snippet alphabetically — the bare-`@` browse
    /// case. A non-empty query keeps only names matching as a subsequence.
    ///
    /// - Parameters:
    ///   - query: the text typed after `@` (without the `@`).
    ///   - limit: the maximum number of results; defaults to 8.
    /// - Returns: the matching snippets, best first, at most `limit`.
    public func matches(for query: String, limit: Int = 8) -> [Snippet] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            return Array(entries.sorted { $0.name.lowercased() < $1.name.lowercased() }.prefix(limit))
        }

        let scored = entries.compactMap { entry -> (entry: Snippet, score: Int)? in
            guard let score = FuzzyMatch.score(query: trimmed, in: entry.name) else { return nil }
            return (entry, score)
        }

        return scored
            .sorted { lhs, rhs in
                lhs.score != rhs.score
                    ? lhs.score > rhs.score
                    : lhs.entry.name.lowercased() < rhs.entry.name.lowercased()
            }
            .prefix(limit)
            .map(\.entry)
    }

    /// The snippet with the given name, or `nil` if absent. Case-insensitive.
    public func snippet(named name: String) -> Snippet? {
        entries.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
