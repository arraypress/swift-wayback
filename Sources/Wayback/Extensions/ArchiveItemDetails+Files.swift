//
//  ArchiveItemDetails+Files.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension ArchiveItemDetails {

    /// The files in a format — `mp3`, `pdf`, `h.264`, `VBR MP3` — matched
    /// against the format name's words and the file extension.
    ///
    /// - Parameters:
    ///   - format: The format; `nil` keeps every file.
    ///   - originalsOnly: Leave out derivatives and the archive's bookkeeping.
    func files(format: String?, originalsOnly: Bool = false) -> [ArchiveFile] {
        ArchiveFormats.select(files, format: format, originalsOnly: originalsOnly)
    }

    /// The file with exactly this name.
    func file(named name: String) -> ArchiveFile? {
        files.first { $0.name == name }
    }

    /// The item's page on archive.org.
    var detailsURL: URL { ArchiveURLs.details(identifier) }
}
