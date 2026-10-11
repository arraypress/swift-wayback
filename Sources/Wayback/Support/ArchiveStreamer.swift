//
//  ArchiveStreamer.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//
//  One file streamed to disk as it arrives. Items run to gigabytes — the
//  most-downloaded Apollo 11 film is 5.5 GB — so the body is read with
//  URLSession's async byte stream and written a megabyte at a time rather
//  than held in memory, and a partial file is continued with a Range
//  request: the storage nodes answer 206 with `accept-ranges: bytes`
//  (measured 2026-10-11, through the 302 from archive.org/download).
//  Cancelling the calling task stops the stream at the next chunk.
//

import CryptoKit
import Foundation

/// Streams one URL onto the end of a file.
enum ArchiveStreamer {

    /// What one request did.
    struct Outcome: Sendable {
        /// The status after redirects; anything but 200 or 206 wrote nothing.
        let status: Int
        /// Bytes this request delivered.
        let fetched: Int64
    }

    /// How much is gathered before each write and progress report.
    static let chunk = 1 << 20

    /// Runs `request` and appends its body to `handle`, which is positioned
    /// at `offset`. A 206 continues the file; a 200 is a whole body — the
    /// server ignored the Range, or none was sent — so the file starts over.
    ///
    /// - Parameters:
    ///   - total: The size the file should reach, when the item records it.
    ///   - progress: Bytes on disk and the total when known, once a chunk.
    static func stream(_ request: URLRequest, onto handle: FileHandle, offset: Int64, total: Int64?,
                       progress: (@Sendable (Int64, Int64?) -> Void)?) async throws -> Outcome {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        var written = offset
        var total = total
        switch status {
        case 206:
            // The total is the part after the slash of `bytes 1000-4999/5000`.
            if let range = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range"),
               let size = range.split(separator: "/").last.flatMap({ Int64($0) }) {
                total = size
            }
        case 200:
            try handle.truncate(atOffset: 0)
            written = 0
            if response.expectedContentLength > 0 { total = response.expectedContentLength }
        default:
            bytes.task.cancel()
            return Outcome(status: status, fetched: 0)
        }

        var fetched: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(chunk)
        func flush() throws {
            guard !buffer.isEmpty else { return }
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
            fetched += Int64(buffer.count)
            buffer.removeAll(keepingCapacity: true)
            progress?(written, total)
        }
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= chunk {
                try flush()
                try Task.checkCancellation()
            }
        }
        try flush()
        return Outcome(status: status, fetched: fetched)
    }

    // MARK: - Checking

    /// A file's MD5 in hex, read in 8 MB chunks so a multi-gigabyte film is
    /// never in memory at once.
    static func md5(of file: URL) throws -> String {
        var hasher = Insecure.MD5()
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// A file's size, or 0 when it is not there.
    static func size(of file: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
