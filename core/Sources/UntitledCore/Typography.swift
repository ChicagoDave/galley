//
//  Typography.swift
//  UntitledCore
//
//  Purpose: Smart-typography substitution (§8) as a pure string transform —
//  curly quotes, em dash, ellipsis — applied to text as it is typed. Kept in the
//  core so the rule is testable headless and identical wherever text is inserted;
//  the shell never re-implements it.
//  Public interface: `smartTypography(inserting:precededBy:)`.
//  Owner context: UntitledCore — UI-free Swift, the model-as-truth (ADR-0004).
//

import Foundation

/// The result of a smart-typography pass: how many characters to remove before
/// the caret, and the text to insert in place of the raw fragment.
///
/// A non-zero `deletePreceding` handles multi-character substitutions typed one
/// key at a time: a second `-` becomes `—` (delete 1, insert `—`); a third `.`
/// becomes `…` (delete 2, insert `…`).
public struct TypographyEdit: Equatable, Sendable {

    /// Characters to delete immediately before the insertion point.
    public let deletePreceding: Int

    /// The text to insert after the deletion.
    public let text: String

    public init(deletePreceding: Int, text: String) {
        self.deletePreceding = deletePreceding
        self.text = text
    }
}

/// Applies smart typography to a freshly typed fragment, given the characters
/// just before the caret (§8).
///
/// - Parameters:
///   - fragment: the raw inserted text (typically one character while typing).
///   - precedingTwo: the two characters before the caret, oldest first
///     (`(offset-2, offset-1)`); either may be `nil` at the start of a block.
/// - Returns: a `TypographyEdit` describing what to delete and insert. Multi-char
///   fragments (e.g. a paste) pass through with only ellipsis collapsing applied.
public func smartTypography(inserting fragment: String, precededBy precedingTwo: (Character?, Character?)) -> TypographyEdit {
    let (prev2, prev1) = precedingTwo

    // Single-character typing: the contextual rules that depend on neighbours.
    if fragment.count == 1, let ch = fragment.first {
        switch ch {
        case "\"":
            return TypographyEdit(deletePreceding: 0, text: opensQuote(after: prev1) ? "\u{201C}" : "\u{201D}")
        case "'":
            return TypographyEdit(deletePreceding: 0, text: opensQuote(after: prev1) ? "\u{2018}" : "\u{2019}")
        case "-" where prev1 == "-":
            return TypographyEdit(deletePreceding: 1, text: "\u{2014}")   // — em dash
        case "." where prev1 == "." && prev2 == ".":
            return TypographyEdit(deletePreceding: 2, text: "\u{2026}")   // … ellipsis
        default:
            return TypographyEdit(deletePreceding: 0, text: fragment)
        }
    }

    // Multi-character fragment (paste / programmatic): collapse literal ellipsis.
    return TypographyEdit(deletePreceding: 0, text: fragment.replacingOccurrences(of: "...", with: "\u{2026}"))
}

/// A quote opens (curls left) at the start of a block or after whitespace or an
/// opening bracket; otherwise it closes (curls right) — including the apostrophe
/// case after a letter.
private func opensQuote(after previous: Character?) -> Bool {
    guard let previous else { return true }
    if previous.isWhitespace { return true }
    return "([{\u{2014}\u{2018}\u{201C}".contains(previous)
}
