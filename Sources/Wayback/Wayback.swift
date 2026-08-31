//
//  Wayback.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//
//  The Internet Archive's Wayback Machine as typed values, keyless. The
//  CDX index is the primary source — fast, rich, filterable; the
//  availability API is DESIGNED for "closest snapshot" but rate-limits
//  aggressively (a probe drew a 429 the day this was written), so it is
//  the fallback, never the first call. Every request carries a
//  descriptive User-Agent, because polite crawler etiquette is what keeps
//  keyless endpoints keyless.
//

import Foundation

/// What can go wrong talking to the archive.
public enum WaybackError: Error, LocalizedError, Sendable, Equatable {
    /// The URL given could not be put into a request.
    case badURL(String)
    /// The archive answered with an HTTP failure.
    case http(Int)
    /// The archive is rate-limiting; retry after this many seconds if known.
    case rateLimited(retryAfter: Int?)
    /// A response did not have the shape the index documents.
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .badURL(let url): return "\(url) is not a URL a request can be made from"
        case .http(let code): return "the archive answered HTTP \(code)"
        case .rateLimited(let after):
            return "the archive is rate-limiting" + (after.map { " (retry after \($0)s)" } ?? "")
        case .malformed(let what): return "unexpected response shape: \(what)"
        }
    }
}

/// A keyless client for the Wayback Machine.
public struct Wayback: Sendable {

    /// How requests are performed — injectable so tests run on recordings.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    /// The User-Agent sent when none is chosen. No personal contact is
    /// baked in; override with something identifying your use.
    public static let defaultUserAgent = "swift-wayback/0.1 (+https://github.com/arraypress/swift-wayback)"

    /// The User-Agent every request carries.
    public let userAgent: String

    private let transport: Transport

    /// A client.
    ///
    /// - Parameters:
    ///   - userAgent: Identify yourself; the archive's keyless endpoints
    ///     stay open because callers do.
    ///   - transport: Leave `nil` for the shared URLSession.
    public init(userAgent: String = Wayback.defaultUserAgent, transport: Transport? = nil) {
        self.userAgent = userAgent
        self.transport = transport ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw WaybackError.malformed("not an HTTP response")
            }
            return (data, http)
        }
    }

    // MARK: - CDX index

    /// Captures of `url`, oldest first.
    ///
    /// - Parameters:
    ///   - url: The page, with or without a scheme.
    ///   - from: Earliest capture to include — `yyyy`, `yyyyMM`, `yyyyMMdd`…
    ///   - to: Latest capture to include, same forms.
    ///   - limit: How many rows; negative counts from the END (`-1` is the
    ///     most recent capture) — the index supports both directions.
    ///   - dedupe: Collapse runs of identical content (same digest), so a
    ///     page captured daily but changed twice comes back twice.
    ///   - onlyOK: Keep only HTTP 200 captures.
    ///   - matchPrefix: Treat `url` as a prefix and list everything under
    ///     it — a whole site's map, one distinct URL per row.
    public func snapshots(of url: String, from: String? = nil, to: String? = nil,
                          limit: Int = 50, dedupe: Bool = true, onlyOK: Bool = true,
                          matchPrefix: Bool = false) async throws -> [Snapshot] {
        var items = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if matchPrefix {
            items.append(URLQueryItem(name: "matchType", value: "prefix"))
            items.append(URLQueryItem(name: "collapse", value: "urlkey"))
        } else if dedupe {
            items.append(URLQueryItem(name: "collapse", value: "digest"))
        }
        if onlyOK { items.append(URLQueryItem(name: "filter", value: "statuscode:200")) }
        if let from { items.append(URLQueryItem(name: "from", value: from)) }
        if let to { items.append(URLQueryItem(name: "to", value: to)) }
        var components = URLComponents(string: "https://web.archive.org/cdx/search/cdx")!
        components.queryItems = items
        guard let endpoint = components.url else { throw WaybackError.badURL(url) }
        let data = try await perform(endpoint)
        return try Self.parseCDX(data)
    }

    /// The capture closest to `timestamp` — the latest at-or-before it,
    /// else the first after; with no timestamp, the most recent capture.
    /// CDX answers first; the availability API is only consulted when the
    /// index itself fails, because it rate-limits.
    public func closest(to url: String, at timestamp: String? = nil) async throws -> Snapshot? {
        do {
            if let timestamp {
                if let before = try await snapshots(of: url, to: timestamp, limit: -1).last { return before }
                return try await snapshots(of: url, from: timestamp, limit: 1).first
            }
            return try await snapshots(of: url, limit: -1).last
        } catch let error as WaybackError {
            if let fallback = try? await availability(of: url, at: timestamp) { return fallback }
            throw error
        }
    }

    // MARK: - Content

    /// The ORIGINAL bytes of a capture — the `id_` form, without the
    /// archive's toolbar or rewritten links.
    public func original(_ snapshot: Snapshot) async throws -> Data {
        try await perform(snapshot.originalBytesURL)
    }

    /// The closest capture and its original bytes in one call.
    public func original(of url: String, at timestamp: String? = nil) async throws -> (snapshot: Snapshot, data: Data)? {
        guard let snapshot = try await closest(to: url, at: timestamp) else { return nil }
        return (snapshot, try await original(snapshot))
    }

    // MARK: - Save Page Now

    /// What a save submission came back with.
    public struct SaveOutcome: Sendable, Equatable {
        /// Whether the archive accepted the request. Acceptance queues a
        /// crawl — the snapshot can take minutes to appear.
        public let submitted: Bool
        /// The HTTP status of the submission.
        public let statusCode: Int
        /// Where the archive said the capture will live, when it said.
        public let location: String?
    }

    /// Asks the archive to capture `url` now. Honest expectations: this
    /// QUEUES a crawl; it does not wait for it.
    public func save(_ url: String) async throws -> SaveOutcome {
        let target = url.hasPrefix("http") ? url : "https://\(url)"
        guard let endpoint = URL(string: "https://web.archive.org/save/\(target)") else {
            throw WaybackError.badURL(url)
        }
        var request = URLRequest(url: endpoint)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (_, response) = try await transport(request)
        let location = response.value(forHTTPHeaderField: "Content-Location")
            ?? response.value(forHTTPHeaderField: "Location")
        return SaveOutcome(submitted: (200...399).contains(response.statusCode),
                           statusCode: response.statusCode, location: location)
    }

    // MARK: - Availability API (fallback only)

    struct Availability: Decodable {
        struct Snapshots: Decodable { let closest: Closest? }
        struct Closest: Decodable { let status: String; let available: Bool; let url: String; let timestamp: String }
        let archived_snapshots: Snapshots
    }

    /// The availability API's answer, shaped like a CDX row. Fallback only:
    /// this endpoint drew a 429 on a single probe the day this was written.
    func availability(of url: String, at timestamp: String?) async throws -> Snapshot? {
        var components = URLComponents(string: "https://archive.org/wayback/available")!
        components.queryItems = [URLQueryItem(name: "url", value: url)]
            + (timestamp.map { [URLQueryItem(name: "timestamp", value: $0)] } ?? [])
        let data = try await perform(components.url!)
        guard let decoded = try? JSONDecoder().decode(Availability.self, from: data) else {
            throw WaybackError.malformed("availability response")
        }
        guard let closest = decoded.archived_snapshots.closest, closest.available else { return nil }
        return Snapshot(timestamp: closest.timestamp, original: url, mimeType: "",
                        statusCode: Int(closest.status), digest: "", length: nil)
    }

    // MARK: - Plumbing

    /// Performs a GET with the User-Agent, retrying a 429 twice with the
    /// archive's own Retry-After (capped at ten seconds) before giving up.
    func perform(_ url: URL, retriesLeft: Int = 2) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport(request)
        switch response.statusCode {
        case 200...299:
            return data
        case 429:
            let after = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            guard retriesLeft > 0 else { throw WaybackError.rateLimited(retryAfter: after) }
            let wait = min(after ?? 1, 10)
            try await Task.sleep(nanoseconds: UInt64(max(wait, 1)) * 1_000_000_000)
            return try await perform(url, retriesLeft: retriesLeft - 1)
        default:
            throw WaybackError.http(response.statusCode)
        }
    }

    /// Parses the CDX JSON — an array of arrays whose FIRST row names the
    /// columns. Parsing is by header name, never by position: the index's
    /// column order is a documented default, not a promise.
    static func parseCDX(_ data: Data) throws -> [Snapshot] {
        guard let rows = try? JSONDecoder().decode([[String]].self, from: data) else {
            throw WaybackError.malformed("CDX response is not an array of string arrays")
        }
        guard let header = rows.first else { return [] }
        let index = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        func field(_ row: [String], _ name: String) -> String? {
            guard let i = index[name], i < row.count else { return nil }
            return row[i]
        }
        guard index["timestamp"] != nil, index["original"] != nil, index["digest"] != nil else {
            throw WaybackError.malformed("CDX header is missing timestamp/original/digest: \(header)")
        }
        return rows.dropFirst().map { row in
            let status = field(row, "statuscode").flatMap { $0 == "-" ? nil : Int($0) }
            let length = field(row, "length").flatMap { $0 == "-" ? nil : Int($0) }
            return Snapshot(timestamp: field(row, "timestamp") ?? "",
                            original: field(row, "original") ?? "",
                            mimeType: field(row, "mimetype") ?? "",
                            statusCode: status,
                            digest: field(row, "digest") ?? "",
                            length: length)
        }
    }
}
