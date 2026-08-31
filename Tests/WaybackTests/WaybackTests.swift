//
//  WaybackTests.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//
//  Everything runs on recorded responses — the fixtures below are real
//  archive output captured 2026-08-31 — so the suite needs no network and
//  cannot be rate-limited into flakiness.
//

import Foundation
import XCTest
@testable import Wayback

final class WaybackTests: XCTestCase {

    // MARK: Recorded fixtures (captured 2026-08-31)

    /// Real CDX output for example.com, verbatim.
    static let cdxReal = """
    [["urlkey","timestamp","original","mimetype","statuscode","digest","length"],
    ["com,example)/","20020120142510","http://example.com:80/","text/html","200","HT2DYGA5UKZCPBSFVCV3JOBXGW2G5UUA","1792"],
    ["com,example)/","20020328012821","http://www.example.com:80/","text/html","200","UY3I2DT2AMWAY6DECFCFYMT5ZOTFHUCH","481"]]
    """

    /// The same rows with the COLUMNS SHUFFLED — the index's order is a
    /// default, not a promise, so parsing must go by header name.
    static let cdxShuffled = """
    [["digest","original","length","timestamp","statuscode","mimetype","urlkey"],
    ["HT2DYGA5UKZCPBSFVCV3JOBXGW2G5UUA","http://example.com:80/","1792","20020120142510","200","text/html","com,example)/"],
    ["ABCDEF","http://example.com/gone","-","20100101000000","-","warc/revisit","com,example)/gone"]]
    """

    /// Real availability output, verbatim.
    static let availabilityReal = """
    {"url": "example.com", "archived_snapshots": {"closest": {"status": "200", "available": true, "url": "http://web.archive.org/web/20160101005048/http://www.example.com/", "timestamp": "20160101005048"}}, "timestamp": "2015"}
    """

    /// A transport that answers from a script and records what was asked.
    final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var requests: [URLRequest] = []
        var answer: @Sendable (URLRequest) -> (Int, Data, [String: String])

        init(_ answer: @escaping @Sendable (URLRequest) -> (Int, Data, [String: String])) {
            self.answer = answer
        }

        /// Sync on purpose: NSLock may not be taken directly in an async
        /// frame, but calling a synchronous method that locks is fine.
        private func record(_ request: URLRequest) {
            lock.lock(); requests.append(request); lock.unlock()
        }

        func transport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            record(request)
            let (code, data, headers) = answer(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
            return (data, response)
        }
    }

    // MARK: Parsing

    func testCDXParsesByHeaderNamesNotPositions() throws {
        let real = try Wayback.parseCDX(Data(Self.cdxReal.utf8))
        XCTAssertEqual(real.count, 2)
        XCTAssertEqual(real[0].timestamp, "20020120142510")
        XCTAssertEqual(real[0].statusCode, 200)
        XCTAssertEqual(real[0].length, 1792)

        let shuffled = try Wayback.parseCDX(Data(Self.cdxShuffled.utf8))
        XCTAssertEqual(shuffled[0].timestamp, "20020120142510", "column order must not matter")
        XCTAssertEqual(shuffled[0].original, "http://example.com:80/")
        XCTAssertEqual(shuffled[0].digest, "HT2DYGA5UKZCPBSFVCV3JOBXGW2G5UUA")
        // The revisit row: '-' status and length become nil, not zero.
        XCTAssertNil(shuffled[1].statusCode)
        XCTAssertNil(shuffled[1].length)
    }

    func testMalformedAndEmptyCDX() throws {
        XCTAssertThrowsError(try Wayback.parseCDX(Data("{\"not\": \"cdx\"}".utf8)))
        XCTAssertThrowsError(try Wayback.parseCDX(Data("[[\"only\",\"nonsense\"]]".utf8)))
        XCTAssertEqual(try Wayback.parseCDX(Data("[]".utf8)), [])
    }

    func testSnapshotURLFormsAndDate() {
        let s = Snapshot(timestamp: "20160101005048", original: "http://www.example.com/",
                         mimeType: "text/html", statusCode: 200, digest: "X", length: 1)
        XCTAssertEqual(s.archiveURL.absoluteString, "https://web.archive.org/web/20160101005048/http://www.example.com/")
        XCTAssertEqual(s.originalBytesURL.absoluteString, "https://web.archive.org/web/20160101005048id_/http://www.example.com/")
        XCTAssertNotNil(s.date)
    }

    // MARK: Query building

    func testSnapshotQueriesCarryTheRightParameters() async throws {
        let script = Script { _ in (200, Data(Self.cdxReal.utf8), [:]) }
        let client = Wayback(transport: script.transport)
        _ = try await client.snapshots(of: "example.com", from: "2010", to: "2020", limit: 7)
        _ = try await client.snapshots(of: "example.com", limit: 5, dedupe: true, onlyOK: false, matchPrefix: true)
        let first = script.requests[0].url!.absoluteString
        XCTAssertTrue(first.contains("collapse=digest"), first)
        XCTAssertTrue(first.contains("filter=statuscode:200"), first)
        XCTAssertTrue(first.contains("from=2010") && first.contains("to=2020") && first.contains("limit=7"), first)
        let second = script.requests[1].url!.absoluteString
        XCTAssertTrue(second.contains("matchType=prefix") && second.contains("collapse=urlkey"), second)
        XCTAssertFalse(second.contains("statuscode"), second)
        XCTAssertEqual(script.requests[0].value(forHTTPHeaderField: "User-Agent"), Wayback.defaultUserAgent)
    }

    // MARK: Closest

    func testClosestPrefersLatestBeforeThenFirstAfter() async throws {
        let empty = Data("[]".utf8)
        let script = Script { request in
            let url = request.url!.absoluteString
            // Nothing at-or-before the asked moment; one capture after it.
            if url.contains("to=1999") { return (200, empty, [:]) }
            if url.contains("from=1999") { return (200, Data(Self.cdxReal.utf8), [:]) }
            return (200, empty, [:])
        }
        let client = Wayback(transport: script.transport)
        let found = try await client.closest(to: "example.com", at: "1999")
        XCTAssertEqual(found?.timestamp, "20020120142510", "must fall through to the first capture AFTER the moment")
    }

    func testRateLimitRetriesWithRetryAfterThenSurfacesHonestly() async throws {
        final class Calls: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            func next() -> Int { lock.lock(); n += 1; let v = n; lock.unlock(); return v }
        }
        let calls = Calls()
        let counter = Script { _ in
            calls.next() < 2 ? (429, Data(), ["Retry-After": "1"]) : (200, Data(WaybackTests.cdxReal.utf8), [:])
        }
        let client = Wayback(transport: counter.transport)
        let rows = try await client.snapshots(of: "example.com")
        XCTAssertEqual(rows.count, 2, "a single 429 with Retry-After must be absorbed")

        let always = Script { _ in (429, Data(), ["Retry-After": "1"]) }
        let stubborn = Wayback(transport: always.transport)
        do {
            _ = try await stubborn.snapshots(of: "example.com")
            XCTFail("persistent 429 must throw")
        } catch let error as WaybackError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 1))
            XCTAssertEqual(always.requests.count, 3, "two retries, then the truth")
        }
    }

    func testAvailabilityFallbackWhenCDXFails() async throws {
        let script = Script { request in
            let url = request.url!.absoluteString
            if url.contains("cdx/search") { return (503, Data(), [:]) }
            return (200, Data(Self.availabilityReal.utf8), [:])
        }
        let client = Wayback(transport: script.transport)
        let found = try await client.closest(to: "example.com", at: "2015")
        XCTAssertEqual(found?.timestamp, "20160101005048")
        XCTAssertEqual(found?.statusCode, 200)
    }

    // MARK: Content and save

    func testOriginalFetchesTheIdForm() async throws {
        let script = Script { request in
            XCTAssertTrue(request.url!.absoluteString.contains("id_/"), "original bytes must use the id_ form")
            return (200, Data("hello".utf8), [:])
        }
        let client = Wayback(transport: script.transport)
        let s = Snapshot(timestamp: "20160101005048", original: "http://example.com/",
                         mimeType: "text/html", statusCode: 200, digest: "X", length: 5)
        let data = try await client.original(s)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "hello")
    }

    func testSaveReportsSubmissionHonestly() async throws {
        let accepted = Script { _ in (302, Data(), ["Location": "https://web.archive.org/web/20260831/https://example.com/x"]) }
        let client = Wayback(transport: accepted.transport)
        let outcome = try await client.save("example.com/x")
        XCTAssertTrue(outcome.submitted)
        XCTAssertEqual(outcome.location, "https://web.archive.org/web/20260831/https://example.com/x")
        XCTAssertTrue(accepted.requests[0].url!.absoluteString.hasPrefix("https://web.archive.org/save/https://example.com/x"))
    }
}
