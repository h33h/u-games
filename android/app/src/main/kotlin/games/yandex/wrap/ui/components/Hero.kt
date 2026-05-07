package games.yandex.wrap.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
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
 * Editorial hero card for Home. Phase 1 STUB: image background + gradient.
 * Phase 2 will add video autoplay through media3 ExoPlayer when game.videoUrl
 * is non-null.
 *
 * 300dp tall, fills width.
 */
@Composable
fun HeroSection(
    game: Game,
    onPlay: () -> Unit,
    onFavorite: () -> Unit,
    onShare: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val haloColor = parseHexColor(game.mainColor) ?: UGColors.Accent
    val placeholder = parseHexColor(game.mainColor) ?: UGColors.Elevated

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(300.dp)
            .shadow(
                elevation = 20.dp,
                shape = RoundedCornerShape(22.dp),
                clip = false,
                ambientColor = haloColor.copy(alpha = UGColors.HaloAlpha),
                spotColor = haloColor.copy(alpha = UGColors.HaloAlpha),
            )
            .clip(RoundedCornerShape(22.dp))
            .background(placeholder)
            .border(
                width = 1.dp,
                color = haloColor.copy(alpha = UGColors.HaloBorderAlpha),
                shape = RoundedCornerShape(22.dp),
            )
            // Tap anywhere on the card opens the same Detail flow as
            // the Play button. Inner clickables (Save / Share / Play
            // now) take precedence at their own bounds.
            .clickable(onClick = onPlay),
    ) {
        AsyncImage(
            model = game.coverUrl,
            contentDescription = game.title,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        0.35f to Color.Transparent,
                        1.0f to Color.Black.copy(alpha = 0.85f),
                    )
                ),
        )
        Row(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(UGColors.Accent.copy(alpha = 0.18f))
                    .padding(horizontal = 10.dp, vertical = 5.dp),
            ) {
                Text(
                    text = "✦ FEATURED TODAY",
                    color = UGColors.Accent,
                    style = UGType.Caption,
                )
            }
            Spacer(Modifier.weight(1f))
            HeroIconButton(icon = Icons.Filled.FavoriteBorder, contentDescription = "Save", onClick = onFavorite)
            Spacer(Modifier.width(8.dp))
            HeroIconButton(icon = Icons.Filled.Share, contentDescription = "Share", onClick = onShare)
        }
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .padding(18.dp),
        ) {
            val chips = listOfNotNull(
                if (game.rating > 0f) "★ %.1f".format(game.rating) else null,
                if (game.ratingCount > 0) "${game.ratingCount} ratings" else null,
                game.categories.firstOrNull(),
            )
            if (chips.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    chips.forEach { chip ->
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(999.dp))
                                .background(Color.White.copy(alpha = 0.08f))
                                .padding(horizontal = 9.dp, vertical = 5.dp),
                        ) {
                            Text(text = chip, color = UGColors.TextSecondary, style = UGType.Caption)
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
            }
            Text(
                text = game.title,
                color = UGColors.TextPrimary,
                style = UGType.Display,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(14.dp))
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(UGColors.AccentGradient)
                    .clickable(onClick = onPlay)
                    .padding(horizontal = 22.dp, vertical = 11.dp),
            ) {
                Text(text = "▶ Play now", color = Color.Black, style = UGType.BodyS)
            }
        }
    }
}

@Composable
private fun HeroIconButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(32.dp)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.5f))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = UGColors.TextPrimary,
            modifier = Modifier.size(16.dp),
        )
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, widthDp = 360, heightDp = 340)
@Composable
private fun HeroSectionPreview() {
    UGamesTheme {
        HeroSection(
            game = Game(
                appId = 1,
                title = "Block Puzzle: Falling Shapes",
                rating = 4.9f, ratingCount = 39,
                coverUrl = "", iconUrl = "",
                categories = listOf("Puzzle"), developer = "studio",
                mainColor = "#41B4F6",
            ),
            onPlay = {}, onFavorite = {}, onShare = {},
            modifier = Modifier.padding(14.dp),
        )
    }
}
