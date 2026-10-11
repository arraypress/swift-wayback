//
//  ArchiveIdentifier.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Item identifiers, and the URLs people paste instead of them.
enum ArchiveIdentifier {

    /// The characters an identifier is made of.
    static let allowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")

    /// The identifier in `text`: the text itself, or the item named by an
    /// archive.org `details`, `download` or `metadata` URL.
    ///
    /// - Throws: ``ArchiveError/badIdentifier(_:)`` for anything else.
    static func parse(_ text: String) throws(ArchiveError) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = trimmed
        if trimmed.contains("archive.org/") {
            let afterHost = trimmed.components(separatedBy: "archive.org/").last ?? ""
            let parts = afterHost.split(separator: "/")
            guard parts.count >= 2, ["details", "download", "metadata", "embed"].contains(String(parts[0])) else {
                throw ArchiveError.badIdentifier(text)
            }
            candidate = String(parts[1].split(whereSeparator: { $0 == "?" || $0 == "#" }).first ?? "")
        }
        guard !candidate.isEmpty, candidate.count <= 100,
              candidate.unicodeScalars.allSatisfy(allowed.contains) else {
            throw ArchiveError.badIdentifier(text)
        }
        return candidate
    }
}
