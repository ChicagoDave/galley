//
//  DocumentBundle.swift
//  GalleyShell
//
//  Purpose: The on-disk representation of a Galley document — a `.galley`
//  bundle directory holding the writer-owned plain-text prose file and its
//  structural JSON sidecar (ADR-0007). The format itself is owned by
//  GalleyCore (`serialize`/`parse`); this type only maps that pair to and
//  from two files on disk.
//  Public interface: `DocumentBundle.read(from:)`, `DocumentBundle.write(_:to:)`,
//  `DocumentBundle.proseFileName`, `DocumentBundle.sidecarFileName`,
//  `DocumentBundle.BundleError`.
//  Owner context: GalleyShell — the macOS shell's file layer. Depends on
//  GalleyCore (the model-as-truth, ADR-0004) and Foundation only; no AppKit.
//

import Foundation
import GalleyCore

/// Reads and writes the on-disk `.galley` bundle: a directory containing the
/// plain-text prose file and its JSON sidecar (ADR-0007).
///
/// The bundle is a directory rather than a single flat file so the prose stays a
/// genuinely plain, independently-openable text file while its structural
/// companion travels alongside it. The directory's `.galley` extension is a
/// convention enforced by the open/save UI, not by this type.
public enum DocumentBundle {

    /// The writer-owned prose file inside a `.galley` bundle directory.
    public static let proseFileName = "prose.txt"

    /// The structural sidecar file inside a `.galley` bundle directory.
    public static let sidecarFileName = "sidecar.json"

    /// A failure reading or writing a bundle on disk.
    ///
    /// Foundation I/O errors and `GalleyCore.ParseError` propagate as-is; this
    /// type names only the failures specific to the bundle layout.
    public enum BundleError: Error, Equatable {

        /// The bundle directory was read but its prose file is absent — the one
        /// file a bundle cannot be reconstructed without.
        case missingProse(URL)
    }

    /// Reads a document from a `.galley` bundle directory.
    ///
    /// - Parameter url: the bundle directory URL.
    /// - Returns: the reconstructed `Document`.
    /// - Throws: `BundleError.missingProse` if the prose file is absent; a
    ///   `GalleyCore.ParseError` if the pair is malformed; or a Foundation I/O
    ///   error if the files cannot be read.
    public static func read(from url: URL) throws -> Document {
        let proseURL = url.appendingPathComponent(proseFileName)
        let sidecarURL = url.appendingPathComponent(sidecarFileName)

        guard FileManager.default.fileExists(atPath: proseURL.path) else {
            throw BundleError.missingProse(proseURL)
        }

        let prose = try String(contentsOf: proseURL, encoding: .utf8)
        // A bundle written by `write(_:to:)` always has a sidecar, but a prose
        // file dropped in by hand may not — treat the sidecar as optional and let
        // the core import the prose alone.
        let sidecar = try? String(contentsOf: sidecarURL, encoding: .utf8)

        return try parse(proseText: prose, sidecar: sidecar)
    }

    /// Writes a document to a `.galley` bundle directory, creating it if needed.
    ///
    /// - Parameters:
    ///   - document: the document to persist.
    ///   - url: the bundle directory URL.
    /// - Throws: a Foundation I/O error if the directory or either file cannot be
    ///   written.
    public static func write(_ document: Document, to url: URL) throws {
        let (prose, sidecar) = serialize(document)

        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        try prose.write(
            to: url.appendingPathComponent(proseFileName),
            atomically: true,
            encoding: .utf8
        )
        try sidecar.write(
            to: url.appendingPathComponent(sidecarFileName),
            atomically: true,
            encoding: .utf8
        )
    }
}
