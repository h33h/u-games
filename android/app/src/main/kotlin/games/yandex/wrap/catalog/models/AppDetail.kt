package games.yandex.wrap.catalog.models

/**
 * Rich game-detail data not exposed by `/feed/`. Sourced from
 * `/games/api/catalogue/v2/get_game` with `format=app`.
 *
 * All fields are optional — a missing field collapses its UI section
 * rather than showing a placeholder.
 */
data class AppDetail(
    /** Long-form description (multi-paragraph, may include `\n`). */
    val description: String?,
    /** Raw screenshot URL or `prefix-url` from the wire response. UI
     *  callers choose the concrete Yandex image size they need. */
    val screenshots: List<String>,
    /** ISO-8601 timestamp when the JSON endpoint carries one. The UI renders
     *  just the year (the only honest "release year" Yandex exposes). */
    val datePublished: String?,
    /** Genre/category labels from `categoriesNames`. */
    val genres: List<String>,
    /** Two-letter language codes (ISO 639) the game is localized for,
     *  e.g. ["ru", "en"]. Empty when JSON-LD doesn't carry the field. */
    val languages: List<String>,
    /** Same semantics as `Game.developer`; kept for detail fallback. */
    val author: String?,
)
