//
//  ArchiveLiveTests.swift
//  WaybackTests
//
//  Created by David Sherlock on 2026.
//
//  The item client against archive.org itself: the edge cases that only
//  the real service can show. Each test SKIPS — never fails — when the
//  archive refuses (no network, a rate limit, a 5xx), so the suite stays a
//  gate on this code rather than on the archive's day. Set WAYBACK_OFFLINE=1
//  to skip them all.
//

import Foundation
import XCTest
@testable import Wayback

final class ArchiveLiveTests: XCTestCase {

    let archive = InternetArchive(userAgent: "swift-wayback-tests/1.2 (+https://github.com/arraypress/swift-wayback)")

    override func setUpWithError() throws {
        if ProcessInfo.processInfo.environment["WAYBACK_OFFLINE"] == "1" { throw XCTSkip("WAYBACK_OFFLINE=1") }
    }

    /// Runs live work, turning the archive's refusals into a skip.
    func live<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as WaybackError {
            switch error {
            case .rateLimited, .http(500...599): throw XCTSkip("archive.org refused: \(error)")
            default: throw error
            }
        } catch let error as URLError {
            throw XCTSkip("no network: \(error.localizedDescription)")
        }
    }

    func testSearchFindsFilteredItems() async throws {
        let query = ArchiveQuery("apollo 11", mediaType: .movies, years: 1969...1969, titleOnly: true, sort: .downloads)
        let page = try await live { try await archive.search(query, limit: 5) }
        XCTAssertGreaterThan(page.total, 5)
        XCTAssertEqual(page.items.count, 5)
        XCTAssertTrue(page.items.allSatisfy { $0.mediaType == .movies && $0.year == 1969 }, "\(page.items)")
        let downloads = page.items.compactMap(\.downloads)
        XCTAssertEqual(downloads, downloads.sorted(by: >), "most downloaded first")
    }

    func testNoResultsIsAnEmptyPageNotAnError() async throws {
        let page = try await live { try await archive.search(ArchiveQuery("zzqxjv qqxzjv wwqzxk"), limit: 5) }
        XCTAssertEqual(page.total, 0)
        XCTAssertTrue(page.items.isEmpty)
    }

    func testSpecialCharactersAndUnicodeAreSearchedNotRejected() async throws {
        for text in ["AC/DC", "[draft]", #"say "hi"#, "C++ (language) ~ ^ : ! ?", "a{b <b> 50% x;y `z` ' a-b",
                     #""apollo 11" moon"#, "東京", "Москва", "क़िताब"] {
            let page = try await live { try await archive.search(ArchiveQuery(text), limit: 1) }
            XCTAssertGreaterThanOrEqual(page.total, 0, text)
        }
        let tokyo = try await live { try await archive.search(ArchiveQuery("東京", titleOnly: true), limit: 3) }
        XCTAssertGreaterThan(tokyo.total, 0)
        XCTAssertTrue(tokyo.items.contains { $0.title.contains("東京") }, "\(tokyo.items.map(\.title))")
    }

    func testScrapeWalksPastTheTenThousandWall() async throws {
        let query = ArchiveQuery(collection: "prelinger", sort: .downloads)
        let first = try await live { try await archive.scrape(query, count: 10_000) }
        XCTAssertGreaterThan(first.total, 10_000, "prelinger held 10,468 items on 2026-10-11")
        XCTAssertEqual(first.items.count, 10_000)
        let cursor = try XCTUnwrap(first.cursor)
        let second = try await live { try await archive.scrape(query, count: 10_000, cursor: cursor) }
        XCTAssertEqual(first.items.count + second.items.count, first.total, "the cursor reaches every item")
        XCTAssertTrue(Set(first.items.map(\.identifier)).isDisjoint(with: second.items.map(\.identifier)))

        // The scrape API's stale-answer trap: a different query right after
        // must get its own result, not prelinger's.
        let none = try await live { try await archive.scrape(ArchiveQuery("zzqxjv qqxzjv wwqzxk"), count: 10_000) }
        XCTAssertEqual(none.total, 0, "another query's answer leaked through")
    }

    func testItemMetadataAndMissingItem() async throws {
        let item = try await live { try await archive.item("Experime1940") }
        let film = try XCTUnwrap(item)
        XCTAssertEqual(film.mediaType, .movies)
        XCTAssertTrue(film.collections.contains("prelinger"))
        XCTAssertFalse(film.files(format: "mp4").isEmpty)
        let missing = try await live { try await archive.item("no_such_item_swift_wayback_2026") }
        XCTAssertNil(missing)
    }

    func testLendingLibraryBookIsRestricted() async throws {
        let item = try await live { try await archive.item("floweringshrubs0000croc_o2s4") }
        let book = try XCTUnwrap(item)
        XCTAssertTrue(book.isRestricted)
        let epub = try XCTUnwrap(book.files.first { $0.format == "EPUB" })
        XCTAssertTrue(epub.isPrivate)
        // Pretend the flag were missing: the server must still refuse, and
        // the refusal must read as restricted, not as a bare HTTP error.
        let unflagged = ArchiveFile(identifier: epub.identifier, name: epub.name, source: epub.source, format: epub.format,
                                    size: epub.size, md5: epub.md5, length: nil, isPrivate: false, url: epub.url)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("restricted-\(UUID().uuidString).epub")
        do {
            _ = try await live { try await archive.download(unflagged, to: destination) }
            XCTFail("a lending-library EPUB must not download")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .restricted(identifier: book.identifier, file: epub.name))
        }
        try? FileManager.default.removeItem(at: destination.appendingPathExtension("part"))
    }

    func testDownloadResumesWithARangeAndChecksMD5() async throws {
        let item = try await live { try await archive.item("Experime1940") }
        let png = try XCTUnwrap(item?.file(named: "Experime1940.png"))
        let size = try XCTUnwrap(png.size)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wayback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent(png.name)

        let fresh = try await live { try await archive.download(png, to: destination) }
        XCTAssertEqual(fresh.bytes, size)
        XCTAssertEqual(fresh.fetched, size)
        XCTAssertTrue(fresh.verified)

        // Cut it in half and leave it where an interrupted attempt would.
        let whole = try Data(contentsOf: destination)
        let half = Int64(whole.count / 2)
        try whole.prefix(Int(half)).write(to: destination.appendingPathExtension("part"))
        try FileManager.default.removeItem(at: destination)
        let resumed = try await live { try await archive.download(png, to: destination) }
        XCTAssertEqual(resumed.resumedFrom, half, "the Range request continued the part")
        XCTAssertEqual(resumed.fetched, size - half)
        XCTAssertTrue(resumed.verified)
        XCTAssertEqual(try Data(contentsOf: destination), whole)

        let again = try await live { try await archive.download(png, to: destination) }
        XCTAssertTrue(again.alreadyComplete)
        XCTAssertEqual(again.fetched, 0)
    }
}
