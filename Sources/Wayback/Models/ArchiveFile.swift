//
//  ArchiveFile.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One file in an item: an upload, or a derivative the archive made from one.
public struct ArchiveFile: Codable, Sendable, Equatable {
    /// The item it belongs to.
    public let identifier: String
    /// The file's name within the item, possibly with folders (`disc1/01.flac`).
    public let name: String
    /// `original` for an upload, `derivative` for what the archive made from
    /// one (an MP3 from a FLAC, a text layer from page scans), `metadata` for
    /// the item's own bookkeeping.
    public let source: String
    /// The archive's format name: `VBR MP3`, `h.264`, `Text PDF`, `EPUB`.
    public let format: String
    /// Bytes; `nil` when the item does not record it.
    public let size: Int64?
    /// The MD5 the archive publishes for it — what a download is checked against.
    public let md5: String?
    /// Running time in seconds, for audio and video.
    public let length: Double?
    /// Whether the file is withheld from download — lending-library books
    /// keep their EPUB and PDF private, and fetching one answers 401.
    public let isPrivate: Bool
    /// Where it downloads from.
    public let url: URL

    /// A file.
    public init(identifier: String, name: String, source: String, format: String, size: Int64?, md5: String?,
                length: Double?, isPrivate: Bool, url: URL) {
        self.identifier = identifier
        self.name = name
        self.source = source
        self.format = format
        self.size = size
        self.md5 = md5
        self.length = length
        self.isPrivate = isPrivate
        self.url = url
    }
}
