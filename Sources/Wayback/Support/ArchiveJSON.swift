//
//  ArchiveJSON.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//
//  Reading the item APIs' JSON, which is loosely typed by design: any
//  metadata field may be a string or a list of them (`collection` is a
//  list, `creator` usually a string, sometimes a list), `year` comes as a
//  number from search and a string from metadata, and a file's `size` is
//  always a string. So it is read through JSONSerialization and a handful
//  of tolerant coercions rather than a Codable shape that would reject the
//  next item that spells a field differently.
//

import Foundation

/// Tolerant parsing of advancedsearch, scrape and metadata responses.
enum ArchiveJSON {

    // MARK: - Coercions

    /// Every string in a value: a string is one, a list gives its strings,
    /// a number its text. Blank entries are dropped.
    static func strings(_ value: Any?) -> [String] {
        switch value {
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        case let list as [Any]:
            return list.flatMap { strings($0) }
        case let number as NSNumber:
            return [number.stringValue]
        default:
            return []
        }
    }

    /// The first string in a value.
    static func string(_ value: Any?) -> String? {
        strings(value).first
    }

    /// A whole number from a number or from a string's leading digits —
    /// `1969`, `"1969"` and `"1969-07-20"` all give 1969.
    static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber:
            return number.int64Value
        case let text as String:
            let digits = text.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }
            return digits.isEmpty ? nil : Int64(digits)
        case let list as [Any]:
            return list.lazy.compactMap { int64($0) }.first
        default:
            return nil
        }
    }

    /// ``int64(_:)`` as an `Int`.
    static func int(_ value: Any?) -> Int? {
        int64(value).map { Int(clamping: $0) }
    }

    /// A running time in seconds, from `"183.45"` or `"03:03"` / `"1:02:03"`.
    static func seconds(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        guard let text = string(value) else { return nil }
        if text.contains(":") {
            let parts = text.split(separator: ":").map { Double($0) }
            guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
            return parts.reduce(0) { $0 * 60 + $1! }
        }
        return Double(text)
    }

    /// Collections a person would call collections: users' favourites lists
    /// (`fav-<username>`) are dropped — the most-downloaded Apollo 11 film
    /// sat in over a thousand of them on 2026-10-11, each naming an account.
    static func collections(_ value: Any?) -> [String] {
        strings(value).filter { !$0.hasPrefix("fav-") }
    }

    // MARK: - Search

    /// One search result from an advancedsearch doc or a scrape item.
    static func item(_ doc: [String: Any]) -> ArchiveItem? {
        guard let identifier = string(doc["identifier"]) else { return nil }
        return ArchiveItem(
            identifier: identifier,
            title: string(doc["title"]) ?? identifier,
            mediaType: string(doc["mediatype"]).flatMap(ArchiveMediaType.init(rawValue:)),
            creators: strings(doc["creator"]),
            date: string(doc["date"]),
            year: int(doc["year"]),
            downloads: int(doc["downloads"]),
            itemSize: int64(doc["item_size"]),
            languages: strings(doc["language"])
        )
    }

    /// The JSON object at the top of a response.
    static func object(_ data: Data, _ what: String) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WaybackError.malformed("\(what) response is not a JSON object")
        }
        return root
    }

    /// The archive's own complaint, when a response carries one. advancedsearch
    /// sends it with HTTP 200, the scrape API with 400; both as `error`.
    static func failure(in root: [String: Any]) -> ArchiveError? {
        guard let message = string(root["error"]) else { return nil }
        if message.contains("DEEP_PAGING") { return .beyondPagingLimit(10_000) }
        return .rejectedQuery(message)
    }

    /// An advancedsearch response.
    static func searchPage(_ data: Data) throws -> ArchiveSearchPage {
        let root = try object(data, "search")
        if let failure = failure(in: root) { throw failure }
        guard let response = root["response"] as? [String: Any],
              let docs = response["docs"] as? [[String: Any]] else {
            throw WaybackError.malformed("search response has no response.docs")
        }
        return ArchiveSearchPage(total: int(response["numFound"]) ?? docs.count,
                                 items: docs.compactMap(item), cursor: nil)
    }

    /// A scrape response. The cursor is absent on the last page.
    static func scrapePage(_ data: Data) throws -> ArchiveSearchPage {
        let root = try object(data, "scrape")
        if let failure = failure(in: root) { throw failure }
        guard let items = root["items"] as? [[String: Any]] else {
            throw WaybackError.malformed("scrape response has no items")
        }
        return ArchiveSearchPage(total: int(root["total"]) ?? items.count,
                                 items: items.compactMap(item), cursor: string(root["cursor"]))
    }

    // MARK: - Metadata

    /// Raw metadata keys left out of ``ArchiveItemDetails/metadata``: each
    /// names a person — scanned books carry the uploader, the scanning
    /// operator and the republisher as e-mail addresses.
    static let withheldKeys: Set<String> = ["uploader", "operator", "republisher_operator", "scanner"]

    /// Whether a value is an e-mail address, which no raw field passes on
    /// whatever key it arrives under.
    static func isEmailAddress(_ text: String) -> Bool {
        text.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    /// A metadata response: `nil` when the item does not exist (the API
    /// answers `{}`), ``ArchiveError/dark(_:)`` when it exists but is dark.
    static func details(_ data: Data, identifier: String) throws -> ArchiveItemDetails? {
        let root = try object(data, "metadata")
        if root.isEmpty { return nil }
        if root["is_dark"] as? Bool == true || string(root["is_dark"]) == "true" {
            throw ArchiveError.dark(identifier)
        }
        guard let metadata = root["metadata"] as? [String: Any] else {
            // Neither absent nor dark, yet no metadata: what an item mid-
            // ingest or otherwise unavailable answers. Treated as not there.
            return nil
        }
        let id = string(metadata["identifier"]) ?? identifier
        let files = (root["files"] as? [[String: Any]] ?? []).compactMap { file(in: id, $0) }
        var raw: [String: [String]] = [:]
        for (key, value) in metadata where !withheldKeys.contains(key) {
            let values = (key == "collection" ? collections(value) : strings(value)).filter { !isEmailAddress($0) }
            if !values.isEmpty { raw[key] = values }
        }
        return ArchiveItemDetails(
            identifier: id,
            title: string(metadata["title"]) ?? id,
            mediaType: string(metadata["mediatype"]).flatMap(ArchiveMediaType.init(rawValue:)),
            creators: strings(metadata["creator"]),
            date: string(metadata["date"]),
            description: strings(metadata["description"]).nilIfEmptyJoined,
            collections: collections(metadata["collection"]),
            languages: strings(metadata["language"]),
            subjects: strings(metadata["subject"]).flatMap { $0.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) } }
                .filter { !$0.isEmpty },
            licenseURL: string(metadata["licenseurl"]),
            publicDate: string(metadata["publicdate"]),
            isRestricted: string(metadata["access-restricted-item"])?.lowercased() == "true",
            itemSize: int64(root["item_size"]),
            files: files,
            metadata: raw
        )
    }

    /// One entry of an item's file list.
    static func file(in identifier: String, _ entry: [String: Any]) -> ArchiveFile? {
        guard let name = string(entry["name"]) else { return nil }
        return ArchiveFile(
            identifier: identifier,
            name: name,
            source: string(entry["source"]) ?? "original",
            format: string(entry["format"]) ?? "",
            size: int64(entry["size"]),
            md5: string(entry["md5"]),
            length: seconds(entry["length"]),
            isPrivate: string(entry["private"])?.lowercased() == "true",
            url: ArchiveURLs.download(identifier, file: name)
        )
    }
}

private extension Array where Element == String {
    /// The entries joined by blank lines, or `nil` when there are none.
    var nilIfEmptyJoined: String? { isEmpty ? nil : joined(separator: "\n\n") }
}
