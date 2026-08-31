//
//  CDX.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//
//  The CDX index's two halves, split from the client so each is testable
//  on its own: building the query (assert the items, no network) and
//  parsing the response (feed it recordings). Parsing is by header NAME,
//  never by position — the index's column order is a documented default,
//  not a promise.
//

import Foundation

/// The CDX index: queries out, snapshots in.
enum CDX {

    /// The search URL for one query. Order of items mirrors the index's
    /// documentation so recorded fixtures stay byte-comparable.
    static func url(for target: String, from: String?, to: String?, limit: Int,
                    dedupe: Bool, onlyOK: Bool, matchPrefix: Bool) throws -> URL {
        var items = [
            URLQueryItem(name: "url", value: target),
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
        guard let url = components.url else { throw WaybackError.badURL(target) }
        return url
    }

    /// Parses the CDX JSON — an array of arrays whose FIRST row names the
    /// columns; `-` marks an absent value.
    static func parse(_ data: Data) throws -> [Snapshot] {
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

/// URL forms the archive accepts.
enum Target {
    /// A user-typed target as a fetchable URL string — bare hosts get https.
    static func normalized(_ url: String) -> String {
        url.hasPrefix("http") ? url : "https://\(url)"
    }
}
