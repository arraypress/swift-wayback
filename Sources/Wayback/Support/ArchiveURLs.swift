//
//  ArchiveURLs.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//
//  Every Internet Archive address the item client uses, built without a
//  network so each is testable. Query strings are encoded by hand:
//  URLComponents leaves `+` alone, PHP decodes it as a space, and an
//  escaped `C\+\+` would reach the archive as `C\  \ `.
//

import Foundation

/// Item search, metadata and download addresses.
enum ArchiveURLs {

    /// The fields a search result is built from.
    static let searchFields = ["identifier", "title", "mediatype", "creator", "date", "year",
                               "downloads", "item_size", "language"]

    /// The characters left bare in a query value; everything else is
    /// percent-encoded, `+` and `&` included.
    static let queryValueAllowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    /// The characters left bare in one path segment: the path set without
    /// the separator itself, `;`, or anything a server might split on.
    static let pathSegmentAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/;?#%"))

    /// `name=value&…`, every value strictly encoded.
    static func queryString(_ items: [(String, String)]) -> String {
        items.map { name, value in
            "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? value)"
        }.joined(separator: "&")
    }

    /// A paged advancedsearch.
    static func search(query: String, sort: ArchiveSort, rows: Int, page: Int) -> URL {
        var items = [("q", query)]
        items += searchFields.map { ("fl%5B%5D", $0) }
        if let field = sort.field { items.append(("sort%5B%5D", field)) }
        items += [("rows", String(rows)), ("page", String(page)), ("output", "json")]
        return URL(string: "https://archive.org/advancedsearch.php?" + queryString(items))!
    }

    /// One page of the scrape API, which walks past advancedsearch's
    /// 10,000-result wall with a cursor.
    ///
    /// The field list ends with a name no item has, unique to the query.
    /// Measured 2026-10-11: the scrape API keeps the result of the FIRST
    /// query it sees for a given `fields` value and answers every later
    /// query with the same fields from it, whatever their `q` — `(zzqxjv)`
    /// came back with apollo 11's 12,195 items, and the stale answer was
    /// still being served minutes later. Unknown field names are accepted
    /// and ignored, so a per-query name gives each query its own answer.
    static func scrape(query: String, sort: ArchiveSort, count: Int, cursor: String?) -> URL {
        let fields = searchFields + [queryKey(query, sort.field ?? "", String(count))]
        var items = [("q", query), ("fields", fields.joined(separator: ",")), ("count", String(count))]
        if let field = sort.field { items.append(("sorts", field)) }
        if let cursor { items.append(("cursor", cursor)) }
        return URL(string: "https://archive.org/services/search/v1/scrape?" + queryString(items))!
    }

    /// A field name derived from the query: `qk_` and a 64-bit FNV-1a hash in
    /// hex, stable across runs (Swift's own `Hasher` is seeded per process).
    static func queryKey(_ parts: String...) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in parts.joined(separator: "\u{1F}").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return "qk_" + String(hash, radix: 16)
    }

    /// An item's metadata and file list.
    static func metadata(_ identifier: String) -> URL {
        URL(string: "https://archive.org/metadata/\(identifier)")!
    }

    /// An item's page.
    static func details(_ identifier: String) -> URL {
        URL(string: "https://archive.org/details/\(identifier)")!
    }

    /// Where one file downloads from — each folder of the name encoded on its
    /// own, so `disc 1/01 #1.flac` keeps its slash and loses nothing else.
    /// The address redirects (302) to the storage node holding the item.
    static func download(_ identifier: String, file: String) -> URL {
        let path = file.split(separator: "/", omittingEmptySubsequences: false).map {
            $0.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? String($0)
        }.joined(separator: "/")
        return URL(string: "https://archive.org/download/\(identifier)/\(path)")!
    }
}
