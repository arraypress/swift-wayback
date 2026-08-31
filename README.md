# Swift Wayback

The Internet Archive's Wayback Machine as typed values — keyless, on any Apple platform.

```swift
import Wayback

let archive = Wayback()
if let snapshot = try await archive.closest(to: "example.com", at: "2015") {
    print(snapshot.timestamp)          // 20151231222136
    print(snapshot.archiveURL)         // the replay page a person reads
    let bytes = try await archive.original(snapshot)   // the ORIGINAL bytes, no toolbar
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
- 📼 **Tested on recordings** — the suite runs on real captured responses with an injected transport: header-order-proof CDX parsing, `-` fields becoming `nil`, the retry dance, the fallback. No network, no flakiness

## Measured

Latency is the archive's, not the library's, and it varies with how heavily a URL is captured: a lightly-archived site answers `closest` in ~2 s; example.com — captured millions of times — takes 20–45 s for tail queries. Original-bytes fetches returned the exact 1,270 bytes of the 2015 capture, verified against content.

## Requirements

macOS 14+ / iOS 16+ / tvOS 16+ / watchOS 9+ / visionOS 1+, Swift 6. Foundation only.

## License

MIT — see LICENSE.
