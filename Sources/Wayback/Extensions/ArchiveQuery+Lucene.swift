//
//  ArchiveQuery+Lucene.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension ArchiveQuery {

    /// The Lucene string this search sends — escaped, filtered, joined.
    ///
    /// - Throws: ``ArchiveError/emptyQuery`` when there is no text and no filter.
    func lucene() throws(ArchiveError) -> String {
        try Lucene.query(for: self)
    }
}
