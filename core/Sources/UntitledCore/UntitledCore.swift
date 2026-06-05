//
//  UntitledCore.swift
//  UntitledCore
//
//  Purpose: Root of the headless domain core for Untitled — the model-as-truth
//  library beneath the macOS editor. The §4 document model, the ADR-0010
//  block-lifecycle operations, parse/serialize, and `revealProjection` arrive
//  in later phases; this file only marks the module in the Phase-1 skeleton.
//  Public interface: `UntitledCore` namespace (placeholder).
//  Owner context: UntitledCore — UI-free Swift, portable per ADR-0002.
//

/// Namespace marker for the headless core module.
///
/// Replaced by the real §4 domain types in Phase 2. Exists so the Phase-1
/// skeleton has a public symbol the test target can import and assert on.
public enum UntitledCore {

    /// The overview §13 build step this module implements.
    public static let phase = "headless-core"
}
