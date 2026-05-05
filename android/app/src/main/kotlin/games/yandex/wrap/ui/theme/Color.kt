package games.yandex.wrap.ui.theme

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/**
 * U-Games premium palette. Token names match the spec
 * (docs/superpowers/specs/2026-05-05-ui-ux-redesign-design.md).
 */
object UGColors {
    val Bg0 = Color(0xFF000000)
    val Surface = Color(0xFF0D0D10)
    val Elevated = Color(0xFF1A1A20)
    val Divider = Color(0xFF1F1F22)

    val TextPrimary = Color(0xFFFFFFFF)
    val TextSecondary = Color(0xFFC8C8D0)
    val TextMuted = Color(0xFF7A7A82)

    val Accent = Color(0xFFFFC700)
    val AccentEnd = Color(0xFFFF7E00)
    val Danger = Color(0xFFFF4D6A)

    /** Glass surface fallback for API < 31 (no blur). */
    val GlassFallback = Color(0xCC141418)

    /** 35% opacity glow used in shadow tints — see Modifier.coloredHalo. */
    val HaloAlpha = 0.35f
    /** 18% opacity inset border. */
    val HaloBorderAlpha = 0.18f

    val AccentGradient: Brush = Brush.linearGradient(
        colors = listOf(Accent, AccentEnd),
    )
}
