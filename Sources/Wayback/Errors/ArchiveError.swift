//
//  ArchiveError.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What can go wrong searching and downloading items. Transport failures —
/// an HTTP error, a rate limit, a response of the wrong shape — still come
/// as ``WaybackError``, since both clients share that plumbing.
public enum ArchiveError: Error, LocalizedError, Sendable, Equatable {
    /// The text is not an item identifier or an archive.org item URL.
    case badIdentifier(String)
    /// The search asked for nothing: no text and no filter.
    case emptyQuery
    /// The archive refused the query, with its reason.
    case rejectedQuery(String)
    /// A paged search cannot reach past the 10,000th result; the scrape API
    /// (``InternetArchive/scrape(_:count:cursor:)``) walks the rest.
    case beyondPagingLimit(Int)
    /// The item exists but is dark: withdrawn from public access.
    case dark(String)
    /// The file is withheld from download — a lending-library book, or a
    /// file the uploader made private.
    case restricted(identifier: String, file: String)
    /// A finished download did not match the MD5 the archive publishes.
    case checksumMismatch(file: String, expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .badIdentifier(let text): return "\(text) is not an Internet Archive item identifier"
        case .emptyQuery: return "a search needs text or at least one filter"
        case .rejectedQuery(let why): return "the archive rejected the query: \(why)"
        case .beyondPagingLimit(let reach):
            return "a paged search stops at 10,000 results (this asked for up to \(reach)); scrape walks the rest"
        case .dark(let identifier): return "\(identifier) exists but is dark — withdrawn from public access"
        case .restricted(let identifier, let file):
            return "\(identifier)/\(file) is withheld from download (lending library or private)"
        case .checksumMismatch(let file, let expected, let actual):
            return "\(file) does not match the archive's MD5 (expected \(expected), got \(actual))"
        }
    }
}
