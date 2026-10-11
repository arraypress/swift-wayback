//
//  ArchiveSearchPage.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// One page of search results.
public struct ArchiveSearchPage: Codable, Sendable, Equatable {
    /// How many items match — not how many came back. On a scrape page
    /// fetched WITH a cursor the archive counts only what remains from that
    /// cursor on: prelinger's second page said 468, not 10,468.
    public let total: Int
    /// This page's items.
    public let items: [ArchiveItem]
    /// Where the next scrape page starts; `nil` when there are no more, and
    /// always `nil` from a paged ``InternetArchive/search(_:limit:page:)``.
    public let cursor: String?

    /// A page.
    public init(total: Int, items: [ArchiveItem], cursor: String?) {
        self.total = total
        self.items = items
        self.cursor = cursor
    }
}
