//
//  ArchiveItem+URLs.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension ArchiveItem {
    /// The item's page on archive.org.
    var detailsURL: URL { ArchiveURLs.details(identifier) }
}
