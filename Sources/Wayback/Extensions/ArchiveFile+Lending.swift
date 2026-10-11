//
//  ArchiveFile+Lending.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension ArchiveFile {

    /// Whether the file is a lending-library copy encrypted for loans —
    /// `LCP Encrypted EPUB`, `LCP Encrypted PDF`. These download without
    /// complaint (they are not marked private) but open only with a loan's
    /// licence, so for reading they are as withheld as a private file.
    var isLendingEncrypted: Bool {
        format.hasPrefix("LCP Encrypted")
    }
}
