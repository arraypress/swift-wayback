//
//  InternetArchive.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//
//  The rest of the Internet Archive — its items: films, books, recordings,
//  software — as typed values, keyless. Search is advancedsearch for the
//  first 10,000 results and the scrape API for everything past them; an
//  item's metadata and file list come from the metadata API; downloads
//  stream to disk, resume with Range requests, and are checked against the
//  MD5 the archive publishes. It lives beside `Wayback` in one module
//  because both talk to the same organisation through the same plumbing:
//  one User-Agent, one transport, one 429 policy.
//

import Foundation

/// A keyless client for Internet Archive items.
///
/// ```swift
/// let archive = InternetArchive()
/// var query = ArchiveQuery("apollo 11", mediaType: .movies, sort: .downloads)
/// let page = try await archive.search(query, limit: 10)
/// if let item = try await archive.item(page.items[0].identifier),
///    let film = item.files(format: "mp4").first {
///     try await archive.download(film, to: URL(fileURLWithPath: film.name))
/// }
/// ```
public struct InternetArchive: Sendable {

    /// The furthest a paged search reaches: `page × limit` may not pass it.
    public static let pagingLimit = 10_000

    /// The User-Agent every request carries.
    public let userAgent: String

    /// User-Agent, transport and 429 policy, shared with ``Wayback``.
    let session: ArchiveSession

    /// A client.
    ///
    /// - Parameters:
    ///   - userAgent: Identify yourself; keyless endpoints stay open because
    ///     callers do.
    ///   - transport: Leave `nil` for the shared URLSession. Downloads always
    ///     stream through URLSession — a transport returns whole bodies.
    ///   - sleeper: How a 429 retry waits; leave `nil` for real sleeping.
    public init(userAgent: String = Wayback.defaultUserAgent, transport: Wayback.Transport? = nil,
                sleeper: Wayback.Sleeper? = nil) {
        self.userAgent = userAgent
        self.session = ArchiveSession(userAgent: userAgent, transport: transport, sleeper: sleeper)
    }

    // MARK: - Search

    /// One page of matching items, in the query's order.
    ///
    /// - Parameters:
    ///   - query: What to look for.
    ///   - limit: Items per page, 1–10,000.
    ///   - page: Which page, from 1. `page × limit` may not pass 10,000 —
    ///     the archive refuses deeper paging; ``scrape(_:count:cursor:)``
    ///     walks the whole result set instead.
    /// - Throws: ``ArchiveError`` for an empty, refused or too-deep query;
    ///   ``WaybackError`` for transport failures.
    public func search(_ query: ArchiveQuery, limit: Int = 50, page: Int = 1) async throws -> ArchiveSearchPage {
        let rows = max(1, min(limit, Self.pagingLimit))
        let page = max(1, page)
        guard page * rows <= Self.pagingLimit else { throw ArchiveError.beyondPagingLimit(page * rows) }
        let url = ArchiveURLs.search(query: try Lucene.query(for: query), sort: query.sort, rows: rows, page: page)
        return try ArchiveJSON.searchPage(try await checked(url))
    }

    /// One page of the scrape API: every matching item, walked by cursor,
    /// with no ceiling — `collection:prelinger` holds 10,468 items, and the
    /// cursor reaches all of them where paging stops at 10,000.
    ///
    /// Relevance order cannot be scraped; a ``ArchiveSort/relevance`` query
    /// comes back in identifier order.
    ///
    /// - Parameters:
    ///   - query: What to look for.
    ///   - count: Items per page, 100–10,000 — the API refuses fewer than 100.
    ///   - cursor: The previous page's ``ArchiveSearchPage/cursor``; `nil` to start.
    public func scrape(_ query: ArchiveQuery, count: Int = 1_000, cursor: String? = nil) async throws -> ArchiveSearchPage {
        let url = ArchiveURLs.scrape(query: try Lucene.query(for: query), sort: query.sort,
                                     count: max(100, min(count, 10_000)), cursor: cursor)
        return try ArchiveJSON.scrapePage(try await checked(url))
    }

    // MARK: - Items

    /// An item's metadata and every file in it.
    ///
    /// - Parameter identifier: The identifier, or an archive.org `details`
    ///   or `download` URL.
    /// - Returns: `nil` when no such item exists.
    /// - Throws: ``ArchiveError/dark(_:)`` when it exists but is withdrawn;
    ///   ``ArchiveError/badIdentifier(_:)`` for text that cannot be one.
    public func item(_ identifier: String) async throws -> ArchiveItemDetails? {
        let id = try ArchiveIdentifier.parse(identifier)
        return try ArchiveJSON.details(try await session.perform(ArchiveURLs.metadata(id)), identifier: id)
    }

    /// Where a file downloads from. Each folder of the name is encoded on its
    /// own; the address redirects to the storage node holding the item.
    public static func downloadURL(identifier: String, file: String) -> URL {
        ArchiveURLs.download(identifier, file: file)
    }

    /// The identifier in an identifier or an archive.org item URL.
    ///
    /// - Throws: ``ArchiveError/badIdentifier(_:)``.
    public static func identifier(from text: String) throws(ArchiveError) -> String {
        try ArchiveIdentifier.parse(text)
    }

    // MARK: - Download

    /// Streams a file to disk, continuing an interrupted attempt. Cancelling
    /// the calling task stops it within a megabyte, leaving the `.part` to
    /// be continued.
    ///
    /// Bytes land in `<destination>.part` and move into place only once
    /// complete and checked, so a cut-off download never looks finished. A
    /// later call finds the `.part` and asks for the rest with a Range
    /// request; a server that ignores the range sends everything and the
    /// file starts over.
    ///
    /// - Parameters:
    ///   - file: From ``ArchiveItemDetails/files``.
    ///   - destination: The file to write.
    ///   - resume: Continue a `.part` left by an earlier attempt, and keep a
    ///     destination that already matches. `false` always fetches afresh.
    ///   - progress: Bytes on disk and the total when known, as they arrive.
    /// - Throws: ``ArchiveError/restricted(identifier:file:)`` for a private
    ///   file (checked before any request, and again if the server answers
    ///   401 or 403); ``ArchiveError/checksumMismatch(file:expected:actual:)``
    ///   when the finished file is not the archive's; ``WaybackError`` for
    ///   other HTTP failures.
    @discardableResult
    public func download(_ file: ArchiveFile, to destination: URL, resume: Bool = true,
                         progress: (@Sendable (Int64, Int64?) -> Void)? = nil) async throws -> ArchiveDownload {
        if file.isPrivate { throw ArchiveError.restricted(identifier: file.identifier, file: file.name) }

        let fileManager = FileManager.default
        if resume, fileManager.fileExists(atPath: destination.path), let size = file.size,
           ArchiveStreamer.size(of: destination) == size,
           try file.md5.map({ try ArchiveStreamer.md5(of: destination) == $0 }) ?? true {
            return ArchiveDownload(destination: destination, bytes: size, resumedFrom: size, fetched: 0,
                                   verified: file.md5 != nil, alreadyComplete: true)
        }

        let part = destination.appendingPathExtension("part")
        if !resume { try? fileManager.removeItem(at: part) }
        var offset = ArchiveStreamer.size(of: part)
        if let size = file.size, offset > size {
            try? fileManager.removeItem(at: part)
            offset = 0
        }
        if !fileManager.fileExists(atPath: part.path) {
            guard fileManager.createFile(atPath: part.path, contents: nil) else {
                throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: part.path])
            }
        }

        var fetched: Int64 = 0
        var resumedFrom = offset
        if offset == 0 || offset != file.size {
            let handle = try FileHandle(forWritingTo: part)
            defer { try? handle.close() }
            try handle.seekToEnd()
            var request = URLRequest(url: file.url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
            let outcome = try await ArchiveStreamer.stream(request, onto: handle, offset: offset,
                                                           total: file.size, progress: progress)
            switch outcome.status {
            case 200: resumedFrom = 0
            case 206: break
            case 401, 403: throw ArchiveError.restricted(identifier: file.identifier, file: file.name)
            case 429: throw WaybackError.rateLimited(retryAfter: nil)
            default: throw WaybackError.http(outcome.status)
            }
            fetched = outcome.fetched
        }

        var verified = false
        if let expected = file.md5 {
            let actual = try ArchiveStreamer.md5(of: part)
            guard actual == expected else {
                try? fileManager.removeItem(at: part)
                throw ArchiveError.checksumMismatch(file: file.name, expected: expected, actual: actual)
            }
            verified = true
        }
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: part, to: destination)
        return ArchiveDownload(destination: destination, bytes: ArchiveStreamer.size(of: destination),
                               resumedFrom: resumedFrom, fetched: fetched, verified: verified,
                               alreadyComplete: false)
    }

    // MARK: - Plumbing

    /// A search GET whose failure body is read before its status: the
    /// archive explains a refused query in JSON, with 200 or 400.
    func checked(_ url: URL) async throws -> Data {
        let (data, status) = try await session.fetch(url)
        if (200...299).contains(status) { return data }
        if let root = try? ArchiveJSON.object(data, "error"), let failure = ArchiveJSON.failure(in: root) {
            throw failure
        }
        throw WaybackError.http(status)
    }
}
