//
//  Lucene.swift
//  Wayback
//
//  Created by David Sherlock on 2026.
//
//  An ArchiveQuery as the Lucene string advancedsearch and the scrape API
//  take. What was measured on 2026-10-11 shapes it:
//
//  - Lucene's backslash escapes do NOT work here. `C\+\+`, `a\-b` and
//    `say \"hi\"` came back as "[BACKEND_ERROR] Invalid or no response from
//    Elasticsearch"; `\[draft\]`, `\~`, `\:` and `\!` broke the response
//    itself — the archive echoes the query into its JSON unescaped, so the
//    reply was not valid JSON. Unescaped, `{`, `<b>`, `%`, `;`, a backtick
//    and a lone `'` failed too.
//  - So user text is made LITERAL rather than escaped: letters and digits
//    in any script are kept, a balanced pair of double quotes stays a
//    phrase, an apostrophe inside a word stays, and every other character
//    becomes a space. That costs nothing a search could have used — the
//    index tokenises on punctuation anyway: `AC/DC` found 20,295 items
//    escaped and `AC DC` 20,299.
//  - The text must be parenthesised. `apollo 11 AND mediatype:movies` binds
//    the AND to `11` alone, so `apollo` matched anything; `(apollo 11) AND
//    mediatype:(movies)` meant what it says.
//

import Foundation

/// Lucene query assembly.
enum Lucene {

    /// The words Lucene reads as operators when upper-case.
    static let operators: Set<String> = ["AND", "OR", "NOT", "TO"]

    /// Text as plain words the archive can search for: see the file header
    /// for what is kept. Upper-case operators are lowered, so `NOT` is
    /// searched for, not obeyed; an empty phrase is dropped, since `""` is
    /// itself an error.
    static func literal(_ text: String) -> String {
        let characters = Array(text)
        let phrases = characters.filter { $0 == "\"" }.count.isMultiple(of: 2)
        var cleaned = ""
        for (index, character) in characters.enumerated() {
            if character.isLetter || character.isNumber || character == "." || character == "_" {
                cleaned.append(character)
            } else if character == "\"" && phrases {
                cleaned.append(" \" ")
            } else if character == "'" || character == "\u{2019}",
                      index > 0, index + 1 < characters.count,
                      characters[index - 1].isLetter, characters[index + 1].isLetter {
                cleaned.append("'")
            } else {
                cleaned.append(" ")
            }
        }
        // Rebuild word by word: quotes back against their phrase, empty
        // phrases gone, operators lowered.
        var words: [String] = []
        var phrase: [String]?
        for word in cleaned.split(whereSeparator: \.isWhitespace).map(String.init) {
            if word == "\"" {
                if let open = phrase {
                    if !open.isEmpty { words.append("\"" + open.joined(separator: " ") + "\"") }
                    phrase = nil
                } else {
                    phrase = []
                }
                continue
            }
            let plain = operators.contains(word) ? word.lowercased() : word
            if phrase != nil { phrase!.append(plain) } else { words.append(plain) }
        }
        return words.joined(separator: " ")
    }

    /// Spellings the archive's `language` field uses for one language — it
    /// holds MARC codes and English names side by side (`eng` and `English`).
    static let languageSpellings: [[String]] = [
        ["eng", "English"], ["fre", "French"], ["ger", "German"], ["spa", "Spanish"],
        ["ita", "Italian"], ["por", "Portuguese"], ["rus", "Russian"], ["jpn", "Japanese"],
        ["chi", "Chinese"], ["ara", "Arabic"], ["dut", "Dutch"], ["lat", "Latin"],
        ["heb", "Hebrew"], ["hin", "Hindi"], ["kor", "Korean"], ["pol", "Polish"],
    ]

    /// Two-letter and alternative codes, onto the MARC code above.
    static let languageAliases: [String: String] = [
        "en": "eng", "fr": "fre", "fra": "fre", "de": "ger", "deu": "ger", "es": "spa",
        "it": "ita", "pt": "por", "ru": "rus", "ja": "jpn", "zh": "chi", "zho": "chi",
        "ar": "ara", "nl": "dut", "nld": "dut", "la": "lat", "he": "heb", "hi": "hin",
        "ko": "kor", "pl": "pol",
    ]

    /// Every spelling of a language the archive is likely to hold.
    static func spellings(ofLanguage language: String) -> [String] {
        let key = language.lowercased()
        let code = languageAliases[key] ?? key
        if let known = languageSpellings.first(where: { $0.contains { $0.lowercased() == code } }) {
            return known
        }
        return [language]
    }

    /// The whole query.
    ///
    /// - Throws: ``ArchiveError/emptyQuery`` when there is nothing to search for.
    static func query(for search: ArchiveQuery) throws(ArchiveError) -> String {
        var clauses: [String] = []
        let text = search.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let body = search.isRaw ? text : literal(text)
            if !body.isEmpty { clauses.append(search.titleOnly ? "title:(\(body))" : "(\(body))") }
        }
        if let type = search.mediaType {
            clauses.append("mediatype:(\(type.rawValue))")
        }
        if let collection = search.collection?.trimmingCharacters(in: .whitespaces), !collection.isEmpty {
            // Quoted, because collection identifiers carry hyphens:
            // `nasa-apollo-multimedia-gallery` found its 46 items this way.
            let id = String(collection.unicodeScalars.filter(ArchiveIdentifier.allowed.contains))
            if !id.isEmpty { clauses.append("collection:(\"\(id)\")") }
        }
        if let creator = search.creator?.trimmingCharacters(in: .whitespaces), !creator.isEmpty {
            let words = literal(creator)
            if !words.isEmpty { clauses.append("creator:(\(words))") }
        }
        if let language = search.language?.trimmingCharacters(in: .whitespaces), !language.isEmpty {
            let names = spellings(ofLanguage: language).map(literal).filter { !$0.isEmpty }
            if !names.isEmpty { clauses.append("language:(\(names.joined(separator: " OR ")))") }
        }
        if let years = search.years {
            clauses.append("year:[\(years.lowerBound) TO \(years.upperBound)]")
        }
        guard !clauses.isEmpty else { throw ArchiveError.emptyQuery }
        return clauses.joined(separator: " AND ")
    }
}
