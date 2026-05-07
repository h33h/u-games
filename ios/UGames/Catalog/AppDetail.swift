import Foundation

/// Rich game-detail data not exposed by `/feed/`. Sourced from the SSR
/// JSON-LD `<script type="application/ld+json">` on the per-app HTML
/// page (`/games/app/<id>`). The catalog feed only carries cover +
/// rating + categories; description/screenshots/published-date are
/// only in the JSON-LD payload.
///
/// All fields are optional — a missing field collapses its UI section
/// rather than showing a placeholder.
struct AppDetail: Equatable {
    /// Long-form description (multi-paragraph, may include `\n`).
    let description: String?
    /// High-res screenshot URLs, already transformed to a UI-friendly
    /// size suffix (`pjpg500x280`) so the Detail row doesn't fetch
    /// multi-MB `/orig` variants.
    let screenshots: [String]
    /// ISO-8601 timestamp from JSON-LD `datePublished`. The UI renders
    /// just the year (the only honest "release year" Yandex exposes).
    let datePublished: String?
    /// All genres listed in JSON-LD. Catalog feed only exposes
    /// `categoriesNames`, which usually overlaps but isn't always
    /// identical (JSON-LD includes audience-targeted genres like "For
    /// boys" that the feed omits).
    let genres: [String]
    /// Two-letter language codes (ISO 639) the game is localized for,
    /// e.g. ["ru", "en"]. Empty when JSON-LD doesn't carry the field.
    let languages: [String]
    /// JSON-LD `author.name`. Same semantics as `Game.developer` —
    /// keep both so the UI can fall back when one is empty.
    let author: String?

    static let empty = AppDetail(
        description: nil, screenshots: [], datePublished: nil,
        genres: [], languages: [], author: nil
    )
}
