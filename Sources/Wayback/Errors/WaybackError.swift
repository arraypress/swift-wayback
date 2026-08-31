//
//  WaybackError.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
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
