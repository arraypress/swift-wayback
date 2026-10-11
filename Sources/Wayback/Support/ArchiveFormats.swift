//
//  ArchiveFormats.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//
//  Picking files out of an item. The archive names formats for people —
//  `VBR MP3`, `128Kbps MP3`, `h.264`, `Text PDF` — so "mp3" has to match a
//  word in the format name or the file's extension, not the name exactly.
//  A well-used audio item carries an original, several derivatives and the
//  archive's own bookkeeping for every track; asking for "mp3" should give
//  the MP3s and nothing else.
//

import Foundation

/// File selection by format.
enum ArchiveFormats {

    /// Whether a file is in the format asked for: its extension, its whole
    /// format name, or one word of the format name, ignoring case and a
    /// leading dot — so `mp3` matches `VBR MP3` and `mp4` matches an `h.264`
    /// file saved as `.mp4`.
    static func matches(_ file: ArchiveFile, format wanted: String) -> Bool {
        var key = wanted.trimmingCharacters(in: .whitespaces).lowercased()
        if key.hasPrefix(".") { key.removeFirst() }
        guard !key.isEmpty else { return true }
        let format = file.format.lowercased()
        if format == key { return true }
        if (file.name as NSString).pathExtension.lowercased() == key { return true }
        let words = format.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return words.contains(key)
    }

    /// The files of an item in a format, optionally originals only.
    static func select(_ files: [ArchiveFile], format: String?, originalsOnly: Bool) -> [ArchiveFile] {
        files.filter { file in
            (!originalsOnly || file.source == "original")
                && (format.map { matches(file, format: $0) } ?? true)
        }
    }
}
