//
//  Timestamp.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//
//  The archive's `yyyyMMddHHmmss` stamps as dates and back — pure
//  fixed-width parsing, no DateFormatter. A formatter would be a shared
//  mutable object smuggled behind a static let; this is a function, so it
//  is thread-safe by construction and testable to the digit.
//

import Foundation

/// The Wayback Machine's timestamp form, both directions.
public enum WaybackTimestamp {

    /// Parses a stamp — full `yyyyMMddHHmmss`, or any of the shortened
    /// forms the index also accepts (`yyyy`, `yyyyMM`, `yyyyMMdd`, …),
    /// padded to the start of the period they name. Returns `nil` for
    /// anything that is not digits in a valid calendar range.
    public static func date(from stamp: String) -> Date? {
        let digits = stamp.filter(\.isNumber)
        guard digits.count == stamp.count, (4...14).contains(digits.count), digits.count % 2 == 0 else { return nil }
        // MMddHHmmss defaults: the first instant of the named period.
        let pad = "0101000000"
        let full = digits + String(pad.dropFirst(digits.count - 4))
        func slice(_ range: Range<Int>) -> Int? {
            let start = full.index(full.startIndex, offsetBy: range.lowerBound)
            let end = full.index(full.startIndex, offsetBy: range.upperBound)
            return Int(full[start..<end])
        }
        guard let year = slice(0..<4), let month = slice(4..<6), let day = slice(6..<8),
              let hour = slice(8..<10), let minute = slice(10..<12), let second = slice(12..<14),
              (1...12).contains(month), (1...31).contains(day),
              hour < 24, minute < 60, second < 60 else { return nil }
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute; components.second = second
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // A rolled-over date (Feb 30 → Mar 2) means the stamp was invalid.
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    /// A date as the archive writes it: full `yyyyMMddHHmmss`, UTC.
    public static func stamp(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02d%02d%02d%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }
}
