//
//  ArchiveTests.swift
//  WaybackTests
//
//  Created by David Sherlock on 2026.
//
//  Item search, metadata and download addressing without a network. The
//  fixtures are trimmed from real responses captured 2026-10-11 — the
//  shapes (a string here, a list there, sizes as strings, `{}` for a
//  missing item, errors inside HTTP 200) are the archive's, not invented.
//

import Foundation
import XCTest
@testable import Wayback

final class ArchiveTests: XCTestCase {

    // MARK: Recorded fixtures (trimmed, captured 2026-10-11)

    /// advancedsearch, "apollo 11" in titles, movies, by downloads.
    static let searchReal = """
    {"responseHeader":{"status":0,"QTime":20},"response":{"numFound":493,"start":0,"docs":[
    {"creator":"NASA/Johnson Space Center","date":"1969-01-01T00:00:00Z","downloads":301179,"identifier":"Apollo1116mmOnboardFilm","item_size":5493529016,"mediatype":"movies","title":"APOLLO 11 16MM ONBOARD FILM","year":1969},
    {"date":"1969-01-01T00:00:00Z","downloads":18287,"identifier":"apolloeleven","item_size":539731729,"mediatype":"movies","title":"Flight of Apollo 11","year":1969},
    {"creator":["One","Two"],"identifier":"gov.archives.arc.45017","language":"English","mediatype":"newkind","year":"1969"}]}}
    """

    /// The scrape API, collection:prelinger by downloads — a cursor and a total.
    static let scrapeReal = """
    {"items":[{"identifier":"AboutBan1935","creator":"Castle Films","title":"About Bananas","year":1935,"item_size":888246012,"downloads":27201884}],
    "count":1,"cursor":"W3siZG93bmxvYWRzIjoxNDgzNzZ9XQ==","total":10468}
    """

    /// Metadata, trimmed from Experime1940 and floweringshrubs0000croc_o2s4.
    static let metadataReal = """
    {"created":1760000000,"d1":"ia600000.us.archive.org","dir":"/0/items/Experime1940","files_count":5,"item_size":1719948065,"server":"ia600000.us.archive.org",
    "metadata":{"identifier":"Experime1940","title":"Experiments in the Revival of Organisms","creator":"Techfilm Studio, Moscow","mediatype":"movies",
    "collection":["prelinger","fav-someone","stock_footage"],"description":"This disturbing film records the successful experiments.","date":"1940","year":"1940",
    "subject":"Animals: Dogs;Medicine: Veterinary: Experiments;Life extension","licenseurl":"http://creativecommons.org/licenses/publicdomain/",
    "publicdate":"2002-07-16 00:00:00","uploader":"someone@example.org","operator":"associate-someone@example.org","runtime":"19:31","access-restricted-item":"true"},
    "files":[
    {"name":"Experime1940.mpeg","source":"original","format":"MPEG2","size":"541226153","md5":"8b93a44424438d74ebd4702e36bbfb7d","length":"1171.97"},
    {"name":"Experime1940.mp4","source":"derivative","format":"h.264","size":"121956872","md5":"b58ec9b61904d447b98775d0b68c97f2","length":"1172.01"},
    {"name":"Experime1940.mp3","source":"derivative","format":"MP3","size":"9372672","md5":"375d2ba3d4f63ec3292717b2c6263457","length":"19:31"},
    {"name":"Experime1940.thumbs/Experime1940_000001.jpg","source":"derivative","format":"Thumbnail","size":"960","md5":"d6c3b54928a1318af9bfa347b02c2073"},
    {"name":"floweringshrubs0000croc_o2s4.epub","source":"derivative","format":"EPUB","size":"72316127","md5":"67f2138291ba0f4c55e0e7fe752bba5f","private":"true"},
    {"name":"Experime1940_files.xml","source":"original","format":"Metadata","md5":"f2b28e67c0aba03b3cb1d23960b4138d"}]}
    """

    // MARK: Lucene

    func testTextIsMadeLiteral() {
        XCTAssertEqual(Lucene.literal("AC/DC"), "AC DC")
        XCTAssertEqual(Lucene.literal("C++ [draft] {x} <b>"), "C draft x b")
        XCTAssertEqual(Lucene.literal(#"a\b; 50% off! `x` ~ ^ : ?"#), "a b 50 off x")
        XCTAssertEqual(Lucene.literal("spider-man's web"), "spider man's web", "an apostrophe inside a word stays")
        XCTAssertEqual(Lucene.literal("' rock 'n' roll '"), "rock n roll", "a lone apostrophe is an error at the archive")
        XCTAssertEqual(Lucene.literal(#""apollo 11" moon"#), #""apollo 11" moon"#, "a balanced phrase stays a phrase")
        XCTAssertEqual(Lucene.literal(#"say "hi"#), "say hi", "an unbalanced quote is dropped")
        XCTAssertEqual(Lucene.literal(#"x "" y "  ""#), "x y", "empty phrases are an error at the archive")
        XCTAssertEqual(Lucene.literal("tom AND jerry NOT TO"), "tom and jerry not to", "upper-case operators are searched for, not obeyed")
        XCTAssertEqual(Lucene.literal("  spaced   out  "), "spaced out")
        XCTAssertEqual(Lucene.literal("東京 Москва क़िताब"), "東京 Москва क़िताब", "every script passes untouched")
        XCTAssertEqual(Lucene.literal("+++ ---"), "")
    }

    func testQueryAssemblesEveryFilter() throws {
        let full = ArchiveQuery("apollo 11", mediaType: .movies, collection: "nasa", creator: "NASA/JSC",
                                language: "en", years: 1969...1972, sort: .downloads)
        XCTAssertEqual(try full.lucene(),
                       #"(apollo 11) AND mediatype:(movies) AND collection:("nasa") AND creator:(NASA JSC) AND language:(eng OR English) AND year:[1969 TO 1972]"#)
        XCTAssertEqual(try ArchiveQuery("apollo 11", titleOnly: true).lucene(), "title:(apollo 11)")
        XCTAssertEqual(try ArchiveQuery(collection: "nasa-apollo-multimedia-gallery").lucene(),
                       #"collection:("nasa-apollo-multimedia-gallery")"#, "filters alone are a query; hyphens survive")
        XCTAssertEqual(try ArchiveQuery("+++", mediaType: .audio).lucene(), "mediatype:(audio)", "text with no words drops out")
        XCTAssertEqual(try ArchiveQuery("subject:(jazz) AND NOT format:(MP3)", isRaw: true).lucene(),
                       "(subject:(jazz) AND NOT format:(MP3))")
        XCTAssertThrowsError(try ArchiveQuery("   ").lucene()) { XCTAssertEqual($0 as? ArchiveError, .emptyQuery) }
        XCTAssertThrowsError(try ArchiveQuery("!!!").lucene()) { XCTAssertEqual($0 as? ArchiveError, .emptyQuery) }
    }

    func testLanguageSpellings() {
        XCTAssertEqual(Lucene.spellings(ofLanguage: "en"), ["eng", "English"])
        XCTAssertEqual(Lucene.spellings(ofLanguage: "English"), ["eng", "English"])
        XCTAssertEqual(Lucene.spellings(ofLanguage: "FRA"), ["fre", "French"])
        XCTAssertEqual(Lucene.spellings(ofLanguage: "Klingon"), ["Klingon"], "unknown languages pass as given")
    }

    func testSortFields() {
        XCTAssertNil(ArchiveSort.relevance.field)
        XCTAssertEqual(ArchiveSort.downloads.field, "downloads desc")
        XCTAssertEqual(ArchiveSort.newest.field, "publicdate desc")
        XCTAssertEqual(ArchiveSort.oldest.field, "date asc")
        XCTAssertEqual(ArchiveSort.title.field, "titleSorter asc")
    }

    // MARK: URLs

    func testSearchURLEncodesStrictly() {
        let url = ArchiveURLs.search(query: #"(a+b) AND year:[1 TO 2]"#, sort: .downloads, rows: 10, page: 2).absoluteString
        XCTAssertTrue(url.hasPrefix("https://archive.org/advancedsearch.php?q="), url)
        XCTAssertTrue(url.contains("a%2Bb"), "a raw + must reach PHP encoded, or it decodes as a space: \(url)")
        XCTAssertFalse(url.contains("+"), url)
        XCTAssertTrue(url.contains("fl%5B%5D=identifier") && url.contains("fl%5B%5D=item_size"), url)
        XCTAssertTrue(url.contains("sort%5B%5D=downloads%20desc") && url.contains("rows=10") && url.contains("page=2"), url)
        XCTAssertTrue(url.hasSuffix("output=json"), url)
        XCTAssertFalse(ArchiveURLs.search(query: "x", sort: .relevance, rows: 1, page: 1).absoluteString.contains("sort"),
                       "relevance sends no sort")
    }

    func testScrapeURLCarriesCursorAndCount() {
        let url = ArchiveURLs.scrape(query: "collection:(prelinger)", sort: .downloads, count: 100, cursor: "W3s=").absoluteString
        XCTAssertTrue(url.hasPrefix("https://archive.org/services/search/v1/scrape?"), url)
        XCTAssertTrue(url.contains("count=100") && url.contains("cursor=W3s%3D") && url.contains("sorts=downloads%20desc"), url)
        XCTAssertTrue(url.contains("fields=identifier%2Ctitle"), url)
    }

    func testEachScrapeQueryGetsItsOwnFieldKey() {
        func key(_ url: URL) -> String? {
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "fields" }?.value?.split(separator: ",").last.map(String.init)
        }
        let apollo = ArchiveURLs.scrape(query: "(apollo 11)", sort: .downloads, count: 100, cursor: nil)
        let again = ArchiveURLs.scrape(query: "(apollo 11)", sort: .downloads, count: 100, cursor: "next")
        let other = ArchiveURLs.scrape(query: "(zzqxjv)", sort: .downloads, count: 100, cursor: nil)
        let resorted = ArchiveURLs.scrape(query: "(apollo 11)", sort: .title, count: 100, cursor: nil)
        XCTAssertEqual(key(apollo), key(again), "a query's pages share a key")
        XCTAssertNotEqual(key(apollo), key(other), "different queries must not share the archive's stale answer")
        XCTAssertNotEqual(key(apollo), key(resorted))
        XCTAssertEqual(key(apollo), ArchiveURLs.queryKey("(apollo 11)", "downloads desc", "100"), "stable across runs")
        XCTAssertTrue(key(apollo)?.hasPrefix("qk_") == true)
    }

    func testDownloadURLEncodesEachSegment() {
        XCTAssertEqual(InternetArchive.downloadURL(identifier: "Experime1940", file: "Experime1940.mp4").absoluteString,
                       "https://archive.org/download/Experime1940/Experime1940.mp4")
        XCTAssertEqual(InternetArchive.downloadURL(identifier: "x", file: "disc 1/01 #1?.flac").absoluteString,
                       "https://archive.org/download/x/disc%201/01%20%231%3F.flac", "folders kept, # and ? encoded")
        XCTAssertEqual(InternetArchive.downloadURL(identifier: "x", file: "Café 100%.mp3").absoluteString,
                       "https://archive.org/download/x/Caf%C3%A9%20100%25.mp3")
    }

    // MARK: Identifiers

    func testIdentifiersAndPastedURLs() throws {
        XCTAssertEqual(try InternetArchive.identifier(from: "Experime1940"), "Experime1940")
        XCTAssertEqual(try InternetArchive.identifier(from: " gov.archives.arc.45017 "), "gov.archives.arc.45017")
        XCTAssertEqual(try InternetArchive.identifier(from: "https://archive.org/details/Experime1940"), "Experime1940")
        XCTAssertEqual(try InternetArchive.identifier(from: "https://archive.org/details/Experime1940?tab=about"), "Experime1940")
        XCTAssertEqual(try InternetArchive.identifier(from: "archive.org/download/Experime1940/Experime1940.mp4"), "Experime1940")
        for bad in ["", "has space", "../etc", "https://archive.org/search?query=x", "a/b", String(repeating: "x", count: 101)] {
            XCTAssertThrowsError(try InternetArchive.identifier(from: bad), bad)
        }
    }

    // MARK: Parsing

    func testSearchParsesLooseTypes() throws {
        let page = try ArchiveJSON.searchPage(Data(Self.searchReal.utf8))
        XCTAssertEqual(page.total, 493)
        XCTAssertNil(page.cursor)
        XCTAssertEqual(page.items.count, 3)
        XCTAssertEqual(page.items[0].identifier, "Apollo1116mmOnboardFilm")
        XCTAssertEqual(page.items[0].itemSize, 5_493_529_016, "past Int32")
        XCTAssertEqual(page.items[0].creators, ["NASA/Johnson Space Center"])
        XCTAssertEqual(page.items[0].mediaType, .movies)
        XCTAssertEqual(page.items[1].creators, [], "no creator is an empty list")
        let third = page.items[2]
        XCTAssertEqual(third.creators, ["One", "Two"], "a list of creators")
        XCTAssertEqual(third.year, 1969, "year as a string")
        XCTAssertEqual(third.title, "gov.archives.arc.45017", "no title falls back to the identifier")
        XCTAssertNil(third.mediaType, "an unknown media type is nil, not a failure")
        XCTAssertEqual(third.languages, ["English"])
        XCTAssertEqual(third.detailsURL.absoluteString, "https://archive.org/details/gov.archives.arc.45017")
    }

    func testSearchErrorsInsideHTTP200() {
        let deep = #"{"error":"[DEEP_PAGING] Deep paging is not supported","responseHeader":{"status":400}}"#
        XCTAssertThrowsError(try ArchiveJSON.searchPage(Data(deep.utf8))) {
            XCTAssertEqual($0 as? ArchiveError, .beyondPagingLimit(10_000))
        }
        let reserved = #"{"error":"reserved character in query"}"#
        XCTAssertThrowsError(try ArchiveJSON.searchPage(Data(reserved.utf8))) {
            XCTAssertEqual($0 as? ArchiveError, .rejectedQuery("reserved character in query"))
        }
        XCTAssertThrowsError(try ArchiveJSON.searchPage(Data("<html>".utf8))) { XCTAssertTrue($0 is WaybackError) }
        let empty = #"{"response":{"numFound":0,"start":0,"docs":[]}}"#
        XCTAssertEqual(try ArchiveJSON.searchPage(Data(empty.utf8)), ArchiveSearchPage(total: 0, items: [], cursor: nil))
    }

    func testScrapeCarriesCursorAndTotal() throws {
        let page = try ArchiveJSON.scrapePage(Data(Self.scrapeReal.utf8))
        XCTAssertEqual(page.total, 10_468)
        XCTAssertEqual(page.cursor, "W3siZG93bmxvYWRzIjoxNDgzNzZ9XQ==")
        XCTAssertEqual(page.items.first?.downloads, 27_201_884)
        let last = #"{"items":[],"count":0,"total":10468}"#
        XCTAssertNil(try ArchiveJSON.scrapePage(Data(last.utf8)).cursor, "the last page has no cursor")
    }

    func testMetadataParses() throws {
        let item = try XCTUnwrap(try ArchiveJSON.details(Data(Self.metadataReal.utf8), identifier: "Experime1940"))
        XCTAssertEqual(item.title, "Experiments in the Revival of Organisms")
        XCTAssertEqual(item.collections, ["prelinger", "stock_footage"], "favourites lists dropped")
        XCTAssertEqual(item.subjects, ["Animals: Dogs", "Medicine: Veterinary: Experiments", "Life extension"])
        XCTAssertEqual(item.itemSize, 1_719_948_065)
        XCTAssertTrue(item.isRestricted)
        XCTAssertNil(item.metadata["uploader"], "an e-mail address is not passed on")
        XCTAssertNil(item.metadata["operator"])
        XCTAssertEqual(item.metadata["runtime"], ["19:31"])
        XCTAssertEqual(item.files.count, 6)
        let mp3 = try XCTUnwrap(item.file(named: "Experime1940.mp3"))
        XCTAssertEqual(mp3.size, 9_372_672, "sizes arrive as strings")
        XCTAssertEqual(mp3.length, 1171, "mm:ss lengths become seconds")
        XCTAssertEqual(item.file(named: "Experime1940.mpeg")?.length, 1171.97)
        XCTAssertTrue(try XCTUnwrap(item.files.first { $0.format == "EPUB" }).isPrivate)
        XCTAssertNil(item.file(named: "Experime1940_files.xml")?.size)
        XCTAssertEqual(item.file(named: "Experime1940.thumbs/Experime1940_000001.jpg")?.url.absoluteString,
                       "https://archive.org/download/Experime1940/Experime1940.thumbs/Experime1940_000001.jpg")
    }

    func testMissingAndDarkItems() throws {
        XCTAssertNil(try ArchiveJSON.details(Data("{}".utf8), identifier: "nope"), "a missing item is {}")
        let dark = #"{"created":1,"dir":"/x","is_dark":true,"server":"ia6"}"#
        XCTAssertThrowsError(try ArchiveJSON.details(Data(dark.utf8), identifier: "gone")) {
            XCTAssertEqual($0 as? ArchiveError, .dark("gone"))
        }
    }

    func testCoercions() {
        XCTAssertEqual(ArchiveJSON.int64("1969-07-20"), 1969)
        XCTAssertNil(ArchiveJSON.int64("circa"))
        XCTAssertEqual(ArchiveJSON.seconds("1:02:03"), 3723)
        XCTAssertNil(ArchiveJSON.seconds("1:xx"))
        XCTAssertEqual(ArchiveJSON.strings(["a", " ", ["b"], 3]), ["a", "b", "3"])
        XCTAssertTrue(ArchiveJSON.isEmailAddress("a.b@example.org"))
        XCTAssertFalse(ArchiveJSON.isEmailAddress("Castle Films"))
    }

    // MARK: Formats

    func testFormatSelection() throws {
        let item = try XCTUnwrap(try ArchiveJSON.details(Data(Self.metadataReal.utf8), identifier: "Experime1940"))
        XCTAssertEqual(item.files(format: "mp3").map(\.name), ["Experime1940.mp3"])
        XCTAssertEqual(item.files(format: "MP4").map(\.name), ["Experime1940.mp4"], "extension matches an h.264 file")
        XCTAssertEqual(item.files(format: "h.264").map(\.name), ["Experime1940.mp4"], "the whole format name matches")
        XCTAssertEqual(item.files(format: ".jpg").count, 1)
        XCTAssertEqual(item.files(format: "mpeg2", originalsOnly: true).map(\.name), ["Experime1940.mpeg"])
        XCTAssertEqual(item.files(format: nil, originalsOnly: true).count, 2)
        XCTAssertTrue(item.files(format: "flac").isEmpty)
    }

    // MARK: Client, offline

    func testDeepPagingRefusedBeforeAnyRequest() async {
        let script = WaybackTests.Script { _ in (200, Data(), [:]) }
        let archive = InternetArchive(transport: script.transport)
        do {
            _ = try await archive.search(ArchiveQuery("x"), limit: 100, page: 101)
            XCTFail("page 101 of 100 is past 10,000")
        } catch {
            XCTAssertEqual(error as? ArchiveError, .beyondPagingLimit(10_100))
        }
        XCTAssertTrue(script.requests.isEmpty)
    }

    func testScrapeRefusalBodyIsRead() async {
        let script = WaybackTests.Script { _ in (400, Data(#"{"error":"bad query syntax"}"#.utf8), [:]) }
        let archive = InternetArchive(transport: script.transport)
        do {
            _ = try await archive.scrape(ArchiveQuery("x"), count: 5)
            XCTFail("a 400 with an error body must throw")
        } catch {
            XCTAssertEqual(error as? ArchiveError, .rejectedQuery("bad query syntax"))
        }
        XCTAssertTrue(script.requests[0].url!.absoluteString.contains("count=100"), "count is raised to the API's floor")
    }

    func testSearchSendsTheUserAgentAndRetries429() async throws {
        final class Calls: @unchecked Sendable {
            private let lock = NSLock(); private var n = 0
            func next() -> Int { lock.lock(); n += 1; let v = n; lock.unlock(); return v }
        }
        let calls = Calls()
        let script = WaybackTests.Script { _ in
            calls.next() == 1 ? (429, Data(), ["Retry-After": "3"]) : (200, Data(ArchiveTests.searchReal.utf8), [:])
        }
        let archive = InternetArchive(userAgent: "test-agent/1", transport: script.transport, sleeper: { _ in })
        let page = try await archive.search(ArchiveQuery("apollo 11", mediaType: .movies), limit: 3)
        XCTAssertEqual(page.items.count, 3)
        XCTAssertEqual(script.requests.count, 2)
        XCTAssertEqual(script.requests[1].value(forHTTPHeaderField: "User-Agent"), "test-agent/1")
    }

    func testMetadataNotFoundAndBadIdentifier() async throws {
        let script = WaybackTests.Script { _ in (200, Data("{}".utf8), [:]) }
        let archive = InternetArchive(transport: script.transport)
        let missing = try await archive.item("https://archive.org/details/no_such_item_x")
        XCTAssertNil(missing)
        XCTAssertEqual(script.requests[0].url!.absoluteString, "https://archive.org/metadata/no_such_item_x")
        do {
            _ = try await archive.item("not an id")
            XCTFail("spaces cannot be in an identifier")
        } catch {
            XCTAssertEqual(error as? ArchiveError, .badIdentifier("not an id"))
        }
    }

    func testPrivateFileRefusedBeforeAnyRequest() async throws {
        let item = try XCTUnwrap(try ArchiveJSON.details(Data(Self.metadataReal.utf8), identifier: "Experime1940"))
        let epub = try XCTUnwrap(item.files(format: "epub").first)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("never-\(UUID().uuidString).epub")
        do {
            try await InternetArchive().download(epub, to: destination)
            XCTFail("a private file must not download")
        } catch {
            XCTAssertEqual(error as? ArchiveError, .restricted(identifier: "Experime1940", file: epub.name))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path + ".part"))
    }
}
