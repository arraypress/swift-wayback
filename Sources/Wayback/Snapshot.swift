//
//  Snapshot.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//
//  One capture of one URL: when the crawler saw it, what came back, and
//  the two addresses that matter — the replay page a person reads, and
//  the `id_` form that returns the ORIGINAL bytes without the archive's
//  toolbar wrapped around them.
//

import Foundation

/// One archived capture of a URL.
public struct Snapshot: Codable, Sendable, Equatable {

    /// When the crawler captured it, as the archive writes it: `yyyyMMddHHmmss`.
    public let timestamp: String
    /// The URL as it was captured (scheme and host as crawled).
    public let original: String
    /// The MIME type the server returned.
    public let mimeType: String
    /// The HTTP status at capture time; `nil` for revisit records, which
    /// the CDX index writes as `-`.
    public let statusCode: Int?
    /// The content digest — identical digests mean the page did not change.
    public let digest: String
    /// Compressed size in the archive, in bytes; `nil` when unrecorded.
    public let length: Int?

    /// A snapshot from the CDX index's values.
    public init(timestamp: String, original: String, mimeType: String,
                statusCode: Int?, digest: String, length: Int?) {
        self.timestamp = timestamp
        self.original = original
        self.mimeType = mimeType
        self.statusCode = statusCode
        self.digest = digest
        self.length = length
    }

    /// The capture instant, parsed from ``timestamp`` (UTC).
    public var date: Date? {
        Self.stamp.date(from: timestamp)
    }

    /// The replay page a person reads — with the archive's toolbar.
    public var archiveURL: URL {
        URL(string: "https://web.archive.org/web/\(timestamp)/\(original)")!
    }

    /// The `id_` address that returns the ORIGINAL bytes, free of the
    /// archive's injected chrome.
    public var originalBytesURL: URL {
        URL(string: "https://web.archive.org/web/\(timestamp)id_/\(original)")!
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmmss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
