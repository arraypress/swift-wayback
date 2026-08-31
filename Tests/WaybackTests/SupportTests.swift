//
//  SupportTests.swift
//  WaybackTests
//
//  Created by David Sherlock on 2026.
//
//  The extracted utilities, tested on their own: timestamps to the digit,
//  the query builder without a network, and a retry that costs no clock.
//

import Foundation
import XCTest
@testable import Wayback

final class SupportTests: XCTestCase {

    func testTimestampsParseFullAndShortFormsAndRefuseNonsense() {
        let full = WaybackTimestamp.date(from: "20150131120000")
        XCTAssertNotNil(full)
        XCTAssertEqual(WaybackTimestamp.stamp(from: full!), "20150131120000", "round trip to the digit")
        XCTAssertEqual(WaybackTimestamp.date(from: "2015"), WaybackTimestamp.date(from: "20150101000000"), "a year means its first instant")
        XCTAssertEqual(WaybackTimestamp.date(from: "201503"), WaybackTimestamp.date(from: "20150301000000"))
        XCTAssertNil(WaybackTimestamp.date(from: "20151340120000"), "month 13 must not roll over")
        XCTAssertNil(WaybackTimestamp.date(from: "20150230000000"), "Feb 30 must not become Mar 2")
        XCTAssertNil(WaybackTimestamp.date(from: "2015-01-31"), "digits only")
        XCTAssertNil(WaybackTimestamp.date(from: "201"), "too short")
        XCTAssertNil(WaybackTimestamp.date(from: "20150"), "odd width")
    }

    func testCDXURLCarriesExactlyTheAskedParameters() throws {
        let url = try CDX.url(for: "example.com", from: "2014", to: "2016", limit: -1,
                              dedupe: true, onlyOK: true, matchPrefix: false)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(value("url"), "example.com")
        XCTAssertEqual(value("limit"), "-1")
        XCTAssertEqual(value("collapse"), "digest")
        XCTAssertEqual(value("filter"), "statuscode:200")
        XCTAssertEqual(value("from"), "2014")
        XCTAssertEqual(value("to"), "2016")

        let prefix = try CDX.url(for: "example.com", from: nil, to: nil, limit: 10,
                                 dedupe: true, onlyOK: false, matchPrefix: true)
        let prefixItems = URLComponents(url: prefix, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(prefixItems.first { $0.name == "matchType" }?.value, "prefix")
        XCTAssertEqual(prefixItems.first { $0.name == "collapse" }?.value, "urlkey",
                       "prefix listing collapses by urlkey, never digest")
        XCTAssertNil(prefixItems.first { $0.name == "filter" })
    }

    func testTargetNormalization() {
        XCTAssertEqual(Target.normalized("example.com"), "https://example.com")
        XCTAssertEqual(Target.normalized("http://old.example.com"), "http://old.example.com")
        XCTAssertEqual(Target.normalized("https://example.com/x"), "https://example.com/x")
    }

    func testRetryUsesTheInjectedSleeperSoTestsCostNoClock() async throws {
        final class Trace: @unchecked Sendable {
            let lock = NSLock(); var calls = 0; var waits: [Int] = []
            func request() -> Int { lock.lock(); calls += 1; let n = calls; lock.unlock(); return n }
            func slept(_ s: Int) { lock.lock(); waits.append(s); lock.unlock() }
        }
        let trace = Trace()
        let limited = HTTPURLResponse(url: URL(string: "https://web.archive.org")!, statusCode: 429,
                                      httpVersion: nil, headerFields: ["Retry-After": "7"])!
        let client = Wayback(transport: { _ in (Data(), limited) }, sleeper: { s in trace.slept(s); _ = trace.request() })
        let started = Date()
        do {
            _ = try await client.snapshots(of: "example.com")
            XCTFail("three 429s must surface as rateLimited")
        } catch let error as WaybackError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 7))
        }
        XCTAssertEqual(trace.waits, [7, 7], "two retries, each honouring Retry-After")
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0, "no real sleeping happened")
    }
}
