//
//  ArchiveMediaType.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// What kind of thing an Internet Archive item is — its `mediatype`.
///
/// Counts on 2026-10-11, for scale: texts 52.6M, web 24.2M, movies 17.3M,
/// audio 14.1M, data 7.5M, image 5.8M, collection 3.7M, software 1.5M,
/// etree (live concert recordings) 296K.
public enum ArchiveMediaType: String, Codable, Sendable, CaseIterable {
    /// Books, papers and other documents.
    case texts
    /// Video: films, television, home movies.
    case movies
    /// Sound: recordings, radio, podcasts, 78s.
    case audio
    /// Programs, disk images, emulated games.
    case software
    /// Still images.
    case image
    /// Live concert recordings from the Live Music Archive.
    case etree
    /// Datasets.
    case data
    /// Web crawls (WARC collections, not Wayback snapshots).
    case web
    /// A collection of other items.
    case collection
    /// A user's account page.
    case account
}
