//
//  InputEvent.swift
//  GalleyCore
//
//  Purpose: The model-coordinate vocabulary of editing intents (§8). The shell's
//  input hooks translate keystrokes into these events; the pure `applyInput`
//  reducer turns each into a model mutation, keeping the model the single source
//  of truth (ADR-0004) and block identities / cut anchors stable (ADR-0010).
//  Coordinates are always model coordinates — a `BlockID` and a character offset
//  within that block — never text-view positions.
//  Public interface: `InputEvent`.
//  Owner context: GalleyCore — UI-free Swift, the model-as-truth (ADR-0004).
//

/// One editing intent expressed in model coordinates (§8).
///
/// The writer never issues these deliberately; the text view's input hooks derive
/// them from keystrokes and the caret, then hand them to `applyInput(_:to:)`.
public enum InputEvent: Equatable, Sendable {

    /// Insert literal text into a paragraph at an in-block character offset. Smart
    /// typography (curly quotes, em dash, ellipsis) is applied contextually.
    case insertText(String, blockID: BlockID, offset: Int)

    /// Enter in a paragraph: split it at `offset` into two paragraphs (§8).
    case splitParagraph(blockID: BlockID, offset: Int)

    /// Enter in a set-piece: break `lineIndex` at `offset` into two preserved
    /// lines (a `[line]`, §7) rather than ending the block.
    case breakSetPieceLine(blockID: BlockID, lineIndex: Int, offset: Int)

    /// Backspace at `offset`: delete the preceding character, or — at offset 0 —
    /// merge with the previous paragraph or remove a preceding scene break.
    case deleteBackward(blockID: BlockID, offset: Int)

    /// Toggle the italic inline mark over the in-block range `start..<end` (§8).
    case toggleItalic(blockID: BlockID, start: Int, end: Int)

    /// Replace an (empty) paragraph with a scene-break ornament — typing `#` or
    /// `***` on an empty line (§8).
    case makeSceneBreak(blockID: BlockID)

    /// Toggle a paragraph to/from a set-piece of `kind` (the verse toggle, §8).
    case toggleSetPiece(blockID: BlockID, kind: SetPieceKind)
}
