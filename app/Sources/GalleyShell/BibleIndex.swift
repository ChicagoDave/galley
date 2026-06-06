//
//  BibleIndex.swift
//  GalleyShell
//
//  Purpose: The reference bible's mechanical lookup surface (§9, ADR-0008) — a
//  fuzzy index over the writer's own entity notes, one Markdown file per entity,
//  read from a `bible/` directory inside the `.galley` package. Loading is plain
//  file I/O and the matching is a pure subsequence scorer; there is no AI and no
//  generation (ADR-0008). Lives in the app layer, not GalleyCore, because it
//  touches the filesystem (ADR-0020); it carries no AppKit, so it is headlessly
//  testable (ADR-0011).
//  Public interface: `BibleIndex`, its `entries`, `load(directory:)`,
//  `matches(for:limit:)`, `entry(named:)`.
//  Owner context: GalleyShell — app-layer reference service. Foundation +
//  GalleyCore (for `BibleEntry`) only; no AppKit.
//

import Foundation
import GalleyCore

/// A fuzzy index over a project's bible entries (§9).
///
/// Each entry is one `*.md` file in the package's `bible/` directory. The entry's
/// canonical name is derived from the filename (`aldous-finch.md` → "Aldous
/// Finch"); a leading `# Heading` line, if present, overrides the display name and
/// the text `@`-complete inserts. The remaining body is the note shown on peek.
/// Reuses `GalleyCore.BibleEntry` as the value type rather than duplicating it.
public struct BibleIndex: Equatable, Sendable {

    /// The indexed entries, in load order (one per bible file).
    public private(set) var entries: [BibleEntry]

    /// Creates an index over an explicit set of entries. The `load(directory:)`
    /// factory is the normal entry point; this initializer exists for composition
    /// and testing.
    public init(entries: [BibleEntry] = []) {
        self.entries = entries
    }

    /// Loads a bible index from a directory of `*.md` files.
    ///
    /// Every `.md` file becomes one entry (`parseEntry`). A missing or unreadable
    /// directory yields an empty index — a project without a bible is normal, not
    /// an error (ADR-0008: lookup is mechanical and optional).
    ///
    /// - Parameter directory: the package's `bible/` directory URL.
    /// - Returns: an index over the directory's entries, or an empty index.
    public static func load(directory: URL) -> BibleIndex {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        let entries = files
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url -> BibleEntry? in
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return parseEntry(filename: url.lastPathComponent, content: content)
            }

        return BibleIndex(entries: entries)
    }

    /// The entries whose name fuzzy-matches `query`, ranked best-first.
    ///
    /// An empty query returns every entry in alphabetical order — the bare-`@`
    /// browse case. A non-empty query keeps only entries whose name contains the
    /// query as a subsequence, ordered by match score then name.
    ///
    /// - Parameters:
    ///   - query: the text typed after `@` (without the `@`).
    ///   - limit: the maximum number of results; defaults to 8.
    /// - Returns: the matching entries, best first, at most `limit`.
    public func matches(for query: String, limit: Int = 8) -> [BibleEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            return Array(entries.sorted { $0.name.lowercased() < $1.name.lowercased() }.prefix(limit))
        }

        let scored = entries.compactMap { entry -> (entry: BibleEntry, score: Int)? in
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

    /// The entry with the given canonical name, or `nil` if absent. Case-insensitive.
    public func entry(named name: String) -> BibleEntry? {
        entries.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: Pure helpers (no I/O; unit-tested directly)

    /// Builds one entry from a bible file's name and contents.
    ///
    /// The canonical name comes from the filename stem, humanised
    /// (`gray-harbor.md` → "Gray Harbor"). A leading `# Heading` line, if present,
    /// overrides both the display name and the text `@`-complete inserts; the rest
    /// of the file is the note shown on peek.
    ///
    /// - Parameters:
    ///   - filename: the file's last path component (e.g. `aldous-finch.md`).
    ///   - content: the file's full text.
    /// - Returns: the parsed entry.
    static func parseEntry(filename: String, content: String) -> BibleEntry {
        let stem = (filename as NSString).deletingPathExtension
        let fromFilename = FuzzyMatch.humanize(stem)

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let firstNonBlank = lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        if let heading = firstNonBlank, heading.hasPrefix("# ") {
            let name = String(heading.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            // Notes: everything after the heading line, leading blank lines trimmed.
            let body = content
                .range(of: heading)
                .map { String(content[$0.upperBound...]) } ?? ""
            return BibleEntry(
                name: name.isEmpty ? fromFilename : name,
                canonicalText: name.isEmpty ? fromFilename : name,
                notes: body.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return BibleEntry(
            name: fromFilename,
            canonicalText: fromFilename,
            notes: content.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
