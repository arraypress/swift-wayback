//
//  ArchiveDownload.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What a download did.
public struct ArchiveDownload: Codable, Sendable, Equatable {
    /// Where the file now is.
    public let destination: URL
    /// Its size on disk.
    public let bytes: Int64
    /// How many of those bytes were already there from an interrupted
    /// attempt — `0` for a fresh download.
    public let resumedFrom: Int64
    /// How many bytes this call fetched.
    public let fetched: Int64
    /// Whether the file was checked against the archive's MD5 and matched;
    /// `false` when the archive publishes no MD5 for it.
    public let verified: Bool
    /// Whether the file was already complete and nothing was fetched.
    public let alreadyComplete: Bool

    /// An outcome.
    public init(destination: URL, bytes: Int64, resumedFrom: Int64, fetched: Int64,
                verified: Bool, alreadyComplete: Bool) {
        self.destination = destination
        self.bytes = bytes
        self.resumedFrom = resumedFrom
        self.fetched = fetched
        self.verified = verified
        self.alreadyComplete = alreadyComplete
    }
}
