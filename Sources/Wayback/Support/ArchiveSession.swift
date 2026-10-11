//
//  ArchiveSession.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//
//  The plumbing both clients share: one User-Agent, one injectable
//  transport, one 429 policy. `Wayback` and `InternetArchive` talk to the
//  same organisation and are rate-limited by the same people, so they are
//  polite in exactly the same way.
//

import Foundation

/// A User-Agent, a transport and a retry policy.
struct ArchiveSession: Sendable {

    /// The User-Agent every request carries.
    let userAgent: String

    /// How requests are performed.
    let transport: Wayback.Transport

    /// How a retry waits.
    let sleeper: Wayback.Sleeper

    init(userAgent: String, transport: Wayback.Transport?, sleeper: Wayback.Sleeper?) {
        self.userAgent = userAgent
        self.sleeper = sleeper ?? { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(seconds, 1)) * 1_000_000_000)
        }
        self.transport = transport ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw WaybackError.malformed("not an HTTP response")
            }
            return (data, http)
        }
    }

    /// One request with the User-Agent set, nothing else done to it.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return try await transport(request)
    }

    /// A GET whose status is the caller's to judge, with a 429 retried twice
    /// on the archive's own Retry-After (capped at ten seconds) first.
    ///
    /// The search endpoints answer a rejected query with a JSON body — some
    /// with HTTP 200, the scrape API with 400 — so the body has to survive a
    /// failure status for the caller to read why.
    func fetch(_ url: URL, retriesLeft: Int = 2) async throws -> (Data, Int) {
        let (data, response) = try await send(URLRequest(url: url))
        guard response.statusCode == 429 else { return (data, response.statusCode) }
        let after = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
        guard retriesLeft > 0 else { throw WaybackError.rateLimited(retryAfter: after) }
        try await sleeper(min(after ?? 1, 10))
        return try await fetch(url, retriesLeft: retriesLeft - 1)
    }

    /// A GET that must succeed: any status outside 2xx throws `.http`.
    func perform(_ url: URL) async throws -> Data {
        let (data, status) = try await fetch(url)
        guard (200...299).contains(status) else { throw WaybackError.http(status) }
        return data
    }
}
