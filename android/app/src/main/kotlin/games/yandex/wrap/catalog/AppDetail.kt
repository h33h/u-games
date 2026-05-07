package games.yandex.wrap.catalog

/**
 * Rich game-detail data not exposed by `/feed/`. Sourced from the SSR
 * JSON-LD `<script type="application/ld+json">` on the per-app HTML
 * page (`/games/app/<id>`). The catalog feed only carries cover +
 * rating + categories; description/screenshots/published-date are only
 * in the JSON-LD payload.
 *
 * All fields are optional — a missing field collapses its UI section
 * rather than showing a placeholder.
 */
data class AppDetail(
    /** Long-form description (multi-paragraph, may include `\n`). */
    val description: String?,
    /** High-res screenshot URLs, already transformed to a UI-friendly
     *  size suffix (`pjpg500x280`) so the Detail row doesn't fetch
     *  multi-MB `/orig` variants. */
    val screenshots: List<String>,
    /** ISO-8601 timestamp from JSON-LD `datePublished`. The UI renders
     *  just the year (the only honest "release year" Yandex exposes). */
    val datePublished: String?,
)
