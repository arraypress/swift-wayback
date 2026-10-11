//
//  ArchiveSort.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// The order search results come back in.
///
/// Relevance is the archive's own ranking, and it ranks loosely: "apollo 11"
/// across every field put radio logs first on 2026-10-11, where
/// ``downloads`` put the mission films first. Relevance is also the one
/// order the scrape API cannot walk — it has no score to sort on — so past
/// the first 10,000 results it falls back to identifier order.
public enum ArchiveSort: String, Codable, Sendable, CaseIterable {
    /// The archive's ranking.
    case relevance
    /// Most downloaded first.
    case downloads
    /// Most recently published to the archive first.
    case newest
    /// Earliest item date first — when the work was made, not uploaded.
    case oldest
    /// Latest item date first.
    case latest
    /// Alphabetical by title.
    case title

    /// The Solr field and direction, or `nil` for relevance.
    var field: String? {
        switch self {
        case .relevance: return nil
        case .downloads: return "downloads desc"
        case .newest: return "publicdate desc"
        case .oldest: return "date asc"
        case .latest: return "date desc"
        case .title: return "titleSorter asc"
        }
    }
}
