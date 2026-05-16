package games.yandex.wrap.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import games.yandex.wrap.catalog.models.Game
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType
import games.yandex.wrap.ui.theme.UGamesTheme
import games.yandex.wrap.ui.theme.parseHexColor

/**
 * Editorial Spotlight card. 22-radius, 160dp, gradient bg from the first
 * cover's mainColor, three smaller covers stacked top-right with tilt,
 * eyebrow + title bottom-left.
 */
@Composable
fun StoryCard(
    title: String,
    subtitle: String,
    games: List<Game>,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val anchor = parseHexColor(games.firstOrNull()?.mainColor) ?: UGColors.Accent
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(160.dp)
            .shadow(
                elevation = 20.dp,
                shape = RoundedCornerShape(22.dp),
                clip = false,
                ambientColor = anchor.copy(alpha = UGColors.HaloAlpha),
                spotColor = anchor.copy(alpha = UGColors.HaloAlpha),
            )
            .clip(RoundedCornerShape(22.dp))
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        anchor.copy(alpha = 0.55f),
                        Color(0xFF0A0418),
                    ),
                )
            )
            .border(
                width = 1.dp,
                color = anchor.copy(alpha = UGColors.HaloBorderAlpha),
                shape = RoundedCornerShape(22.dp),
            )
            .clickable(onClick = onClick),
    ) {
        val sample = games.take(3)
        sample.forEachIndexed { index, g ->
            val placeholder = parseHexColor(g.mainColor) ?: UGColors.Elevated
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 24.dp)
                    .offset(x = (-14 - index * 8).dp)
                    .rotate(degrees = (-8 + index * 8).toFloat())
                    .size(42.dp)
                    .shadow(elevation = 6.dp, shape = RoundedCornerShape(10.dp), clip = false)
                    .clip(RoundedCornerShape(10.dp))
                    .background(placeholder),
            ) {
                AsyncImage(
                    model = g.iconUrl("pjpg256x256"),
                    contentDescription = g.title,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        0.5f to Color.Transparent,
                        1.0f to Color.Black.copy(alpha = 0.6f),
                    )
                ),
        )
        Column(
            modifier = Modifier.align(Alignment.BottomStart).padding(18.dp),
        ) {
            Text(text = subtitle, color = UGColors.TextSecondary, style = UGType.Label)
            Text(
                text = title,
                color = UGColors.TextPrimary,
                style = UGType.TitleL,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, widthDp = 360, heightDp = 200)
@Composable
private fun StoryCardPreview() {
    UGamesTheme {
        StoryCard(
            title = "5 brain-bending puzzles to try this week",
            subtitle = "SPOTLIGHT · ISSUE #04",
            games = listOf(
                Game(1, "A", 0f, 0, "", "", emptyList(), "", "#9B6CFF", "#9B6CFF"),
                Game(2, "B", 0f, 0, "", "", emptyList(), "", "#43E890", "#43E890"),
                Game(3, "C", 0f, 0, "", "", emptyList(), "", "#FF7EB9", "#FF7EB9"),
            ),
            onClick = {},
            modifier = Modifier.padding(14.dp),
        )
    }
}
