package games.yandex.wrap.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Parse a "#RRGGBB" or "#AARRGGBB" hex string into a Compose [Color]. Returns
 * null for blank, malformed, or wrong-length strings — callers should fall
 * back to a default (e.g. UGColors.Surface).
 *
 * Yandex catalog feed exposes mainColor as "#41B4F6" lowercase or uppercase.
 */
fun parseHexColor(hex: String?): Color? {
    if (hex.isNullOrBlank()) return null
    val cleaned = hex.removePrefix("#")
    return when (cleaned.length) {
        6 -> runCatching { Color(("ff$cleaned").toLong(16)) }.getOrNull()
        8 -> runCatching { Color(cleaned.toLong(16)) }.getOrNull()
        else -> null
    }
}
