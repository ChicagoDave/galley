//
//  EditorLayout.swift
//  Galley
//
//  Purpose: The caret ↔ model bridge for the editable surface. Walks the block
//  stream and builds the `NSAttributedString` (via `Attribution`) while recording,
//  per piece, which `BlockID` it came from and the text-view character range it
//  occupies — so the input layer can map a caret to a model `(blockID, offset)`
//  and back after a re-render (§8, ADR-0003).
//  Public interface: `EditorLayout.build(from:)`, `modelPosition(forCharacterAt:)`,
//  `characterPosition(forBlock:offset:)`, `firstEditablePosition()`.
//  Owner context: Galley — the macOS shell's editing layer.
//
//  Note: offsets are converted between the model's Character counts and the text
//  view's UTF-16 positions via the live string, so multi-unit characters map
//  correctly. Set-pieces render but are not inline-editable in Phase 3 (toggle a
//  paragraph to verse to create one; toggle back to edit it).
//

import AppKit
import GalleyCore

struct EditorLayout {

    /// One contiguous run of the rendered string and what it maps to.
    struct Segment {
        /// Range in the attributed string. For an editable segment this excludes
        /// the trailing paragraph newline, so the caret at the range's end is the
        /// end of the block.
        let utf16Range: NSRange
        /// The block this segment renders, or `nil` for pure decoration
        /// (chapter headings).
        let blockID: BlockID?
        /// Whether the caret may sit in this segment and edits apply to its block.
        let editable: Bool
        /// The block's plain text, for Character ↔ UTF-16 offset conversion. Empty
        /// for non-editable segments.
        let text: String
    }

    let attributedString: NSAttributedString
    let segments: [Segment]

    /// Builds the editable layout for a document.
    static func build(from doc: Document) -> EditorLayout {
        let out = NSMutableAttributedString()
        var segments: [Segment] = []

        func append(_ piece: NSAttributedString, blockID: BlockID?, editable: Bool, text: String) {
            let start = out.length
            out.append(piece)
            // The piece ends with a paragraph newline; the editable region excludes it.
            let length = editable ? max(0, piece.length - 1) : piece.length
            segments.append(Segment(
                utf16Range: NSRange(location: start, length: length),
                blockID: blockID, editable: editable, text: text
            ))
        }

        func spans(_ runs: [Run]) -> [DisplaySpan] {
            runs.filter { !$0.text.isEmpty }.map { DisplaySpan(text: $0.text, italic: $0.italic) }
        }

        for block in doc.blocks {
            for cut in doc.cuts where cut.blockID == block.id && cut.offsetInBlock == nil {
                append(Attribution.attributedString(for: [.chapterStart(title: cut.title)]),
                       blockID: nil, editable: false, text: "")
            }

            switch block.content {
            case .paragraph(let runs):
                let piece = Attribution.attributedString(for: [.paragraph(spans: spans(runs), overrides: block.overrides)])
                append(piece, blockID: block.id, editable: true, text: runs.map(\.text).joined())

            case .sceneBreak:
                append(Attribution.attributedString(for: [.sceneBreak]), blockID: block.id, editable: false, text: "")

            case .setPiece(let kind, let lines):
                for line in lines {
                    append(Attribution.attributedString(for: [.setPieceLine(kind: kind, spans: spans(line), overrides: block.overrides)]),
                           blockID: block.id, editable: false, text: "")
                }
            }
        }

        return EditorLayout(attributedString: out, segments: segments)
    }

    /// Maps a text-view character position to a model `(blockID, offset)`, or `nil`
    /// if it falls in non-editable decoration.
    func modelPosition(forCharacterAt position: Int) -> (blockID: BlockID, offset: Int)? {
        let nsString = attributedString.string as NSString
        for segment in segments where segment.editable {
            guard let id = segment.blockID else { continue }
            let lower = segment.utf16Range.location
            let upper = lower + segment.utf16Range.length
            if position >= lower && position <= upper {
                let prefix = nsString.substring(with: NSRange(location: lower, length: position - lower))
                return (id, prefix.count)
            }
        }
        return nil
    }

    /// Maps a model `(blockID, offset)` to a text-view character position, or `nil`
    /// if the block is not present as an editable segment.
    func characterPosition(forBlock blockID: BlockID, offset: Int) -> Int? {
        guard let segment = segments.first(where: { $0.editable && $0.blockID == blockID }) else { return nil }
        let characters = Array(segment.text)
        let clamped = min(max(offset, 0), characters.count)
        let prefix = String(characters[0..<clamped]) as NSString
        return segment.utf16Range.location + prefix.length
    }

    /// The caret position at the start of the first editable block, if any.
    func firstEditablePosition() -> (blockID: BlockID, offset: Int)? {
        guard let segment = segments.first(where: { $0.editable }), let id = segment.blockID else { return nil }
        return (id, 0)
    }
}
