//
//  ArchiveQuery.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// An Internet Archive item search: free text plus typed filters.
///
/// The text is taken literally: punctuation becomes word breaks, so `AC/DC`
/// and `[draft]` search for their words rather than reaching the archive as
/// Lucene syntax it rejects, and a pair of double quotes still makes a
/// phrase. Set ``isRaw`` to send Lucene as written.
///
/// ```swift
/// var query = ArchiveQuery("apollo 11")
/// query.mediaType = .movies
/// query.years = 1969...1972
/// query.sort = .downloads
/// ```
public struct ArchiveQuery: Codable, Sendable, Equatable {

    /// Words to look for; every word must match. `"apollo 11"` in double
    /// quotes matches the phrase.
    public var text: String

    /// Only items of this kind.
    public var mediaType: ArchiveMediaType?

    /// Only items in this collection, by its identifier (`prelinger`, `nasa`).
    public var collection: String?

    /// Only items by this creator.
    public var creator: String?

    /// Only items in this language — a code (`eng`, `fre`) or a name
    /// (`English`); the common ones match both spellings the archive uses.
    public var language: String?

    /// Only items dated within these years.
    public var years: ClosedRange<Int>?

    /// Match the text against titles only — far tighter than every field.
    public var titleOnly: Bool

    /// The order of results.
    public var sort: ArchiveSort

    /// Send ``text`` as Lucene, unescaped: `subject:(jazz) AND NOT format:(MP3)`.
    public var isRaw: Bool

    /// A search.
    public init(_ text: String = "", mediaType: ArchiveMediaType? = nil, collection: String? = nil,
                creator: String? = nil, language: String? = nil, years: ClosedRange<Int>? = nil,
                titleOnly: Bool = false, sort: ArchiveSort = .relevance, isRaw: Bool = false) {
        self.text = text
        self.mediaType = mediaType
        self.collection = collection
        self.creator = creator
        self.language = language
        self.years = years
        self.titleOnly = titleOnly
        self.sort = sort
        self.isRaw = isRaw
    }
}
