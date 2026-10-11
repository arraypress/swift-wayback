# Swift Wayback

The Internet Archive as typed values — keyless, on any Apple platform: the Wayback Machine's snapshots of any URL, and (since 1.2.0) the archive's items — films, books, recordings, software — searched, described and downloaded.

```swift
import Wayback

let archive = Wayback()
if let snapshot = try await archive.closest(to: "example.com", at: "2015") {
    print(snapshot.timestamp)          // 20151231222136
    print(snapshot.archiveURL)         // the replay page a person reads
    let bytes = try await archive.original(snapshot)   // the ORIGINAL bytes, no toolbar
}
```

```swift
let items = InternetArchive()
let page = try await items.search(ArchiveQuery("apollo 11", mediaType: .movies, titleOnly: true, sort: .downloads), limit: 10)
if let film = try await items.item(page.items[0].identifier),
   let mp4 = film.files(format: "mp4").first {
    try await items.download(mp4, to: URL(fileURLWithPath: mp4.name)) { done, total in /* progress */ }
}
```

## Features

- 🕰️ **Snapshots as values** — timestamp, status, digest, size, and both URLs that matter: the replay page and the `id_` form that returns the original bytes without the archive's injected chrome
- 🔎 **The CDX index first** — fast, filterable, and honest about what it holds; listings collapse unchanged captures (same digest), so a page crawled daily but changed twice lists twice
- 🧭 **`closest(to:at:)`** — the latest capture at-or-before a moment, else the first after; the availability API is the *fallback*, never the first call, because it rate-limits (a single probe drew a 429 the day this was written)
- 🚦 **429s handled like an adult** — Retry-After honoured, two retries, then a typed `rateLimited` error
- 🗺️ **Whole-site listings** — `matchPrefix` walks everything archived under a domain or path
- 💾 **Save Page Now** — submit a capture request, reported honestly as *queued*, because that is what it is
- 🪪 **Polite by default** — every request carries a descriptive User-Agent (override it with something identifying your use; etiquette is what keeps keyless endpoints keyless)
- 📚 **Item search with typed filters** — media type, collection, creator, language (`en`, `eng` and `English` all match), year range, title-only, six sorts; `isRaw` sends Lucene as written
- 🧱 **Past the 10,000 wall** — `search` pages through advancedsearch's first 10,000 results; `scrape` walks every match by cursor
- 🗂️ **Items in full** — metadata and every file (format, size, MD5, length, private flag), `files(format: "mp3")` matching `VBR MP3` and an `h.264` saved as `.mp4` alike; `nil` for a missing item, `ArchiveError.dark` for a withdrawn one
- ⬇️ **Downloads that survive** — streamed to `<name>.part` through URLSession's async byte stream, continued with a Range request, moved into place only once the archive's MD5 matches; cancelling the task stops within a megabyte
- 🔒 **Lending-library books said plainly** — private files throw `restricted` before any request (and a 401/403 maps to the same), `isLendingEncrypted` marks the LCP copies that download but open only on loan
- 📼 **Tested on recordings** — the suite runs on real captured responses with an injected transport: header-order-proof CDX parsing, `-` fields becoming `nil`, the retry dance, the fallback, query building, URL encoding, loose item JSON. 34 offline tests, plus 7 live item tests that skip (never fail) when archive.org refuses; `WAYBACK_OFFLINE=1` skips them

## Measured

Latency is the archive's, not the library's, and it varies with how heavily a URL is captured: a lightly-archived site answers `closest` in ~2 s; example.com — captured millions of times — takes 20–45 s for tail queries. Original-bytes fetches returned the exact 1,270 bytes of the 2015 capture, verified against content.

## Measured — items (2026-10-11)

- **Ordering.** On four probes ("apollo 11" movies, "moby dick" texts, "grateful dead 1977" etree, "doom" software) title-only + `.downloads` put the item a person meant first 4 of 4 times; every-field `.relevance` 0 of 4 (radio logs, a blog dump, a `.wad`). The library defaults stay neutral; `wayback search` uses title + downloads.
- **Speed.** A 10-row search ~1.8 s; walking `collection:prelinger` past the wall — 10,468 items, no duplicates — 14.8 s in two scrape pages. A 323-file concert item narrowed to its 63 MP3s in 1.8 s.
- **Downloads.** 122 MB in 48 s at 11% CPU (the archive's pace, not the stream's). Interrupted at 31.5 MB, the next call fetched exactly the remaining 51.6 MB with a Range request, and the MD5 matched.

Archive traps found on the way, each handled and tested:

- **Lucene backslash escapes do not work.** `C\+\+`, `a\-b` and `\"` gave `[BACKEND_ERROR]`; `\[`, `\~`, `\:` and `\!` made the reply invalid JSON (the query is echoed back unescaped). So text is made literal instead — letters and digits in any script kept, a balanced `"phrase"` kept, all other punctuation a word break — which loses nothing: `AC/DC` escaped found 20,295 items, `AC DC` 20,299.
- **Errors arrive as HTTP 200** with an `error` key (`[DEEP_PAGING]`, "reserved character"); the scrape API uses 400. Both are read and typed.
- **The scrape API serves stale answers.** It keeps the result of the first query it sees for a given `fields` value and returns it for every later query with the same fields — `(zzqxjv)` came back with apollo 11's 12,195 items, minutes later. Each query therefore sends one extra, unknown field name derived from the query (unknown fields are accepted and ignored).
- **A scrape page after the first counts what remains**, not the whole (prelinger's second page said 468).
- **Collections include users' favourites lists** (`fav-<username>`; over a thousand on the top Apollo 11 film) — dropped, as are metadata fields that name people (`uploader`, `operator`, any e-mail address).
- **Dark items** are read from the metadata API's `is_dark` flag; no dark item could be found to confirm it live (the Wayback lookup used to hunt one was rate-limited), so that path is tested on a fixture only.

## Requirements

macOS 14+ / iOS 16+ / tvOS 16+ / watchOS 9+ / visionOS 1+, Swift 6 language mode. Foundation and CryptoKit (for the MD5 check) only.

## License

MIT — see LICENSE.
