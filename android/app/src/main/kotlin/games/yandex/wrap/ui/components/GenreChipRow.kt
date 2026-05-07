package games.yandex.wrap.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType
import games.yandex.wrap.ui.theme.UGamesTheme

/**
 * Horizontal scroll of genre chips. The first chip is always "All" (passes
 * null as the selected category).
 */
@Composable
fun GenreChipRow(
    genres: List<String>,
    selected: String?,
    onSelect: (String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    val items = listOf<String?>(null) + genres
    // Vertical contentPadding gives the active chip's accent shadow
    // halo (8dp elevation) breathing room. Without it the shadow
    // gets clipped by the LazyRow's measured viewport.
    LazyRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 12.dp),
    ) {
        items(items) { genre ->
            val active = genre == selected
            val label = genre ?: "All"
            val bg = if (active) UGColors.Accent else UGColors.Surface
            val fg = if (active) UGColors.Bg0 else UGColors.TextSecondary
            val borderColor = if (active) UGColors.Accent else UGColors.Divider
            val shadowMod = if (active) {
                Modifier.shadow(
                    elevation = 8.dp,
                    shape = RoundedCornerShape(999.dp),
                    clip = false,
                    ambientColor = UGColors.Accent.copy(alpha = 0.4f),
                    spotColor = UGColors.Accent.copy(alpha = 0.4f),
                )
            } else Modifier
            Text(
                text = label,
                style = UGType.BodyS,
                color = fg,
                modifier = Modifier
                    .then(shadowMod)
                    .clip(RoundedCornerShape(999.dp))
                    .background(bg)
                    .border(1.dp, borderColor, RoundedCornerShape(999.dp))
                    .clickable { onSelect(genre) }
                    .padding(horizontal = 14.dp, vertical = 8.dp),
            )
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, widthDp = 400, heightDp = 60)
@Composable
private fun GenreChipRowPreview() {
    UGamesTheme {
        GenreChipRow(
            genres = listOf("Action", "Puzzle", "Racing", "Casual", "Word"),
            selected = "Puzzle",
            onSelect = {},
            modifier = Modifier.padding(vertical = 8.dp),
        )
    }
}
