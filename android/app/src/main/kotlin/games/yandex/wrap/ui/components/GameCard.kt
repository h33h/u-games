package games.yandex.wrap.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import games.yandex.wrap.catalog.Game
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType
import games.yandex.wrap.ui.theme.UGamesTheme
import games.yandex.wrap.ui.theme.parseHexColor

/**
 * Tile card for grids (Browse / Favorites / Similar).
 *
 * - Cover at 16:10 with mainColor placeholder fallback (no grey flash).
 * - Heart toggle top-right on a glass-circle.
 * - Rating pill bottom-left.
 * - Halo: shadow tinted by mainColor, falls back to Accent if unknown.
 * - Title 2 lines max, meta 1 line.
 */
@Composable
fun TileGameCard(
    game: Game,
    isFavorite: Boolean,
    onClick: () -> Unit,
    onFavoriteToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val haloColor = parseHexColor(game.mainColor) ?: UGColors.Accent
    val placeholder = parseHexColor(game.mainColor) ?: UGColors.Elevated

    Column(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .clickable(onClick = onClick),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(16f / 10f)
                .shadow(
                    elevation = 12.dp,
                    shape = RoundedCornerShape(16.dp),
                    clip = false,
                    ambientColor = haloColor.copy(alpha = UGColors.HaloAlpha),
                    spotColor = haloColor.copy(alpha = UGColors.HaloAlpha),
                )
                .clip(RoundedCornerShape(16.dp))
                .background(placeholder)
                .border(
                    width = 1.dp,
                    color = haloColor.copy(alpha = UGColors.HaloBorderAlpha),
                    shape = RoundedCornerShape(16.dp),
                ),
        ) {
            AsyncImage(
                model = game.coverUrl,
                contentDescription = game.title,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxWidth().aspectRatio(16f / 10f),
            )
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(8.dp)
                    .size(30.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.55f))
                    .clickable(onClick = onFavoriteToggle),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = if (isFavorite) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                    contentDescription = if (isFavorite) "Remove from favorites" else "Add to favorites",
                    tint = if (isFavorite) UGColors.Danger else UGColors.TextPrimary,
                    modifier = Modifier.size(16.dp),
                )
            }
            if (game.ratingCount > 0) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(8.dp)
                        .clip(RoundedCornerShape(999.dp))
                        .background(Color.Black.copy(alpha = 0.55f))
                        .padding(horizontal = 8.dp, vertical = 3.dp),
                ) {
                    Text(
                        text = "★ %.1f".format(game.rating),
                        color = UGColors.Accent,
                        style = UGType.Caption,
                    )
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(
            text = game.title,
            color = UGColors.TextPrimary,
            style = UGType.BodyS,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        val meta = listOfNotNull(
            game.categories.firstOrNull(),
            if (game.ratingCount > 0) "${game.ratingCount} ratings" else null,
        ).joinToString(" · ")
        if (meta.isNotEmpty()) {
            Text(
                text = meta,
                color = UGColors.TextMuted,
                style = UGType.Caption,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, widthDp = 200, heightDp = 220)
@Composable
private fun TileGameCardPreview() {
    UGamesTheme {
        TileGameCard(
            game = Game(
                appId = 1, title = "Block Puzzle: Falling Shapes",
                rating = 4.9f, ratingCount = 39,
                coverUrl = "", iconUrl = "",
                categories = listOf("Puzzle"), developer = "studio",
                mainColor = "#41B4F6",
            ),
            isFavorite = true,
            onClick = {}, onFavoriteToggle = {},
            modifier = Modifier.padding(12.dp),
        )
    }
}

/**
 * Wide card (140×96) for Continue / Trending / Favorites rows on Home.
 * Title overlaid bottom, full-bleed cover, halo by mainColor.
 */
@Composable
fun WideGameCard(
    game: Game,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val haloColor = parseHexColor(game.mainColor) ?: UGColors.Accent
    val placeholder = parseHexColor(game.mainColor) ?: UGColors.Elevated
    Box(
        modifier = modifier
            .size(width = 140.dp, height = 96.dp)
            .shadow(
                elevation = 12.dp,
                shape = RoundedCornerShape(16.dp),
                clip = false,
                ambientColor = haloColor.copy(alpha = UGColors.HaloAlpha),
                spotColor = haloColor.copy(alpha = UGColors.HaloAlpha),
            )
            .clip(RoundedCornerShape(16.dp))
            .background(placeholder)
            .border(
                width = 1.dp,
                color = haloColor.copy(alpha = UGColors.HaloBorderAlpha),
                shape = RoundedCornerShape(16.dp),
            )
            .clickable(onClick = onClick),
    ) {
        AsyncImage(
            model = game.coverUrl,
            contentDescription = game.title,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxWidth().height(96.dp),
        )
        Box(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(8.dp),
        ) {
            Text(
                text = game.title,
                color = UGColors.TextPrimary,
                style = UGType.Caption,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, widthDp = 180, heightDp = 130)
@Composable
private fun WideGameCardPreview() {
    UGamesTheme {
        WideGameCard(
            game = Game(
                appId = 1, title = "Drift King",
                rating = 4.5f, ratingCount = 12,
                coverUrl = "", iconUrl = "",
                categories = listOf("Racing"), developer = "studio",
                mainColor = "#FFC700",
            ),
            onClick = {},
            modifier = Modifier.padding(12.dp),
        )
    }
}
