//
//  ArchiveItem.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One search result: enough to choose an item, not its files.
public struct ArchiveItem: Codable, Sendable, Equatable {
    /// The item's unique identifier — what ``InternetArchive/item(_:)`` takes.
    public let identifier: String
    /// Its title; falls back to the identifier when the item has none.
    public let title: String
    /// What kind of item it is; `nil` for a media type this library predates.
    public let mediaType: ArchiveMediaType?
    /// Who made it, in the order the item lists them.
    public let creators: [String]
    /// The item's own date as it gives it — `1969`, `1969-07-20`, an ISO stamp.
    public let date: String?
    /// The year the archive indexed for it.
    public let year: Int?
    /// Lifetime downloads.
    public let downloads: Int?
    /// Every file in the item together, in bytes.
    public let itemSize: Int64?
    /// The languages it declares, as written (`eng`, `English`).
    public let languages: [String]

    /// A result.
    public init(identifier: String, title: String, mediaType: ArchiveMediaType?, creators: [String],
                date: String?, year: Int?, downloads: Int?, itemSize: Int64?, languages: [String]) {
        self.identifier = identifier
        self.title = title
        self.mediaType = mediaType
        self.creators = creators
        self.date = date
        self.year = year
        self.downloads = downloads
        self.itemSize = itemSize
        self.languages = languages
    }
}
