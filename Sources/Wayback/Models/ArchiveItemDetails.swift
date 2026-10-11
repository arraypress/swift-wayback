//
//  ArchiveItemDetails.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// An item in full: its description, where it is filed, and every file.
public struct ArchiveItemDetails: Codable, Sendable, Equatable {
    /// The item's unique identifier.
    public let identifier: String
    /// Its title; falls back to the identifier when the item has none.
    public let title: String
    /// What kind of item it is.
    public let mediaType: ArchiveMediaType?
    /// Who made it.
    public let creators: [String]
    /// The item's own date as it gives it.
    public let date: String?
    /// The description, as the uploader wrote it — often HTML.
    public let description: String?
    /// The collections it belongs to. Users' favourites lists (`fav-…`) are
    /// left out: a popular film is in thousands of them, and they name people.
    public let collections: [String]
    /// The languages it declares.
    public let languages: [String]
    /// Its subject keywords.
    public let subjects: [String]
    /// The licence it is offered under, when it says.
    public let licenseURL: String?
    /// When it was published to the archive.
    public let publicDate: String?
    /// Whether it is a lending-library item: viewable by loan, its book
    /// files withheld from download.
    public let isRestricted: Bool
    /// Every file in the item together, in bytes.
    public let itemSize: Int64?
    /// Every file, originals and derivatives alike.
    public let files: [ArchiveFile]
    /// Every metadata field as the item holds it, single values as
    /// one-element lists — for the fields the curated ones leave out.
    public let metadata: [String: [String]]

    /// An item.
    public init(identifier: String, title: String, mediaType: ArchiveMediaType?, creators: [String],
                date: String?, description: String?, collections: [String], languages: [String],
                subjects: [String], licenseURL: String?, publicDate: String?, isRestricted: Bool,
                itemSize: Int64?, files: [ArchiveFile], metadata: [String: [String]]) {
        self.identifier = identifier
        self.title = title
        self.mediaType = mediaType
        self.creators = creators
        self.date = date
        self.description = description
        self.collections = collections
        self.languages = languages
        self.subjects = subjects
        self.licenseURL = licenseURL
        self.publicDate = publicDate
        self.isRestricted = isRestricted
        self.itemSize = itemSize
        self.files = files
        self.metadata = metadata
    }
}
