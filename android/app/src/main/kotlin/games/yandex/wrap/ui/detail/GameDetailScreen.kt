package games.yandex.wrap.ui.detail

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import games.yandex.wrap.catalog.Game
import games.yandex.wrap.ui.components.Skeleton
import games.yandex.wrap.ui.components.TileGameCard
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType
import games.yandex.wrap.ui.theme.parseHexColor

/**
 * Phase 3 push screen between any catalog card and the WebView.
 *
 * Sections (top to bottom):
 *  1. Hero (360dp): cover + mainColor halo + sticky top icons (← / ♥ / ↗)
 *  2. Title block (eyebrow + DisplayXL + stat-chips)
 *  3. Stats grid (Genre / Rating / Ratings)
 *  4. More like this (LazyRow of TileGameCard)
 *
 * Plus a sticky bottom CTA (▶ Play now) with a 3-impulse pulse.
 */
@Composable
fun GameDetailScreen(
    viewModel: GameDetailViewModel,
    onBack: () -> Unit,
    onPlay: (Game) -> Unit,
    onShare: (Game) -> Unit,
    onSimilarClick: (Game) -> Unit,
    onSimilarFavoriteToggle: (Game) -> Unit,
) {
    val state by viewModel.state.collectAsState()
    val game = state.game

    val systemBarsPadding: PaddingValues = WindowInsets.systemBars.asPaddingValues()
    val statusBarsPadding: PaddingValues = WindowInsets.statusBars.asPaddingValues()

    Box(modifier = Modifier.fillMaxSize().background(UGColors.Bg0)) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                top = 0.dp,
                bottom = systemBarsPadding.calculateBottomPadding() + 110.dp,
            ),
        ) {
            item {
                DetailHero(
                    game = game,
                    isFavorite = state.isFavorite,
                    topInset = statusBarsPadding.calculateTopPadding(),
                    onBack = onBack,
                    onFavorite = viewModel::toggleFavorite,
                    onShare = { onShare(game) },
                )
            }
            item { Spacer(Modifier.height(20.dp)) }
            item { TitleBlock(game = game) }
            item { Spacer(Modifier.height(18.dp)) }
            item { StatsGrid(game = game) }
            item { Spacer(Modifier.height(24.dp)) }
            item {
                Text(
                    text = "More like this",
                    color = UGColors.TextPrimary,
                    style = UGType.TitleM,
                    modifier = Modifier.padding(horizontal = 18.dp),
                )
                Spacer(Modifier.height(12.dp))
            }
            item {
                SimilarRow(
                    similar = state.similar,
                    isLoading = state.isLoadingSimilar,
                    error = state.similarError,
                    favoriteIds = state.favoriteIds,
                    onClick = onSimilarClick,
                    onFavoriteToggle = onSimilarFavoriteToggle,
                )
            }
        }
        StickyPlayCta(
            game = game,
            bottomInset = systemBarsPadding.calculateBottomPadding(),
            onPlay = { onPlay(game) },
        )
    }
}

@Composable
private fun DetailHero(
    game: Game,
    isFavorite: Boolean,
    topInset: androidx.compose.ui.unit.Dp,
    onBack: () -> Unit,
    onFavorite: () -> Unit,
    onShare: () -> Unit,
) {
    val haloColor = parseHexColor(game.mainColor) ?: UGColors.Accent
    val placeholder = parseHexColor(game.mainColor) ?: UGColors.Elevated
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(360.dp + topInset)
            .background(placeholder)
            .border(
                width = 1.dp,
                color = haloColor.copy(alpha = UGColors.HaloBorderAlpha),
                shape = RoundedCornerShape(0.dp),
            ),
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
                        0.30f to Color.Transparent,
                        1.00f to UGColors.Bg0,
                    )
                ),
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = topInset + 10.dp, start = 14.dp, end = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            HeroIcon(icon = Icons.Filled.ArrowBack, contentDescription = "Back", onClick = onBack)
            Spacer(Modifier.weight(1f))
            HeroIcon(
                icon = if (isFavorite) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                contentDescription = if (isFavorite) "Remove from favorites" else "Add to favorites",
                tint = if (isFavorite) UGColors.Danger else UGColors.TextPrimary,
                onClick = onFavorite,
            )
            Spacer(Modifier.width(8.dp))
            HeroIcon(icon = Icons.Filled.Share, contentDescription = "Share", onClick = onShare)
        }
    }
}

@Composable
private fun HeroIcon(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    tint: Color = UGColors.TextPrimary,
) {
    Box(
        modifier = Modifier
            .size(36.dp)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.55f))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = tint,
            modifier = Modifier.size(18.dp),
        )
    }
}

@Composable
private fun TitleBlock(game: Game) {
    val haloColor = parseHexColor(game.mainColor) ?: UGColors.Accent
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp)) {
        val eyebrow = game.categories.firstOrNull()?.uppercase()
        if (!eyebrow.isNullOrEmpty()) {
            Text(
                text = "$eyebrow · GAME",
                color = UGColors.TextMuted,
                style = UGType.Label,
            )
            Spacer(Modifier.height(8.dp))
        }
        Text(
            text = game.title,
            color = UGColors.TextPrimary,
            style = UGType.DisplayXL,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
        )
        Spacer(Modifier.height(12.dp))
        val chips = listOfNotNull(
            if (game.rating > 0f) "★ %.1f".format(game.rating) else null,
            if (game.ratingCount > 0) "${game.ratingCount} ratings" else null,
            "No ads",
        )
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            chips.forEachIndexed { idx, chip ->
                val isAds = idx == chips.size - 1
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(999.dp))
                        .background(
                            if (isAds) haloColor.copy(alpha = 0.18f)
                            else Color.White.copy(alpha = 0.08f)
                        )
                        .padding(horizontal = 9.dp, vertical = 5.dp),
                ) {
                    Text(
                        text = chip,
                        color = if (isAds) haloColor else UGColors.TextSecondary,
                        style = UGType.Caption,
                    )
                }
            }
        }
    }
}

@Composable
private fun StatsGrid(game: Game) {
    val genre = game.categories.firstOrNull()?.replaceFirstChar { it.uppercase() } ?: "—"
    val rating = if (game.rating > 0f) "★ %.1f".format(game.rating) else "—"
    val ratingCount = if (game.ratingCount > 0) game.ratingCount.toString() else "—"
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        StatCard(eyebrow = "GENRE", value = genre, modifier = Modifier.weight(1f))
        StatCard(eyebrow = "RATING", value = rating, modifier = Modifier.weight(1f))
        StatCard(eyebrow = "RATINGS", value = ratingCount, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun StatCard(eyebrow: String, value: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(14.dp))
            .background(UGColors.Surface)
            .padding(horizontal = 12.dp, vertical = 14.dp),
    ) {
        Text(text = eyebrow, color = UGColors.TextMuted, style = UGType.Label)
        Spacer(Modifier.height(6.dp))
        Text(
            text = value,
            color = UGColors.TextPrimary,
            style = UGType.TitleM,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun SimilarRow(
    similar: List<Game>,
    isLoading: Boolean,
    error: String?,
    favoriteIds: Set<Long>,
    onClick: (Game) -> Unit,
    onFavoriteToggle: (Game) -> Unit,
) {
    when {
        isLoading -> LazyRow(
            contentPadding = PaddingValues(horizontal = 18.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(3) {
                Skeleton(
                    modifier = Modifier
                        .width(160.dp)
                        .height(140.dp),
                    cornerRadius = 16.dp,
                )
            }
        }
        error != null && similar.isEmpty() -> Text(
            text = "Couldn't load related games",
            color = UGColors.TextMuted,
            style = UGType.BodyS,
            modifier = Modifier.padding(horizontal = 18.dp),
        )
        similar.isEmpty() -> {
            // No related games — render nothing so the row collapses.
        }
        else -> LazyRow(
            contentPadding = PaddingValues(horizontal = 18.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(items = similar, key = { it.appId }) { g ->
                Box(modifier = Modifier.width(160.dp)) {
                    TileGameCard(
                        game = g,
                        isFavorite = favoriteIds.contains(g.appId),
                        onClick = { onClick(g) },
                        onFavoriteToggle = { onFavoriteToggle(g) },
                    )
                }
            }
        }
    }
}

@Composable
private fun StickyPlayCta(
    game: Game,
    bottomInset: androidx.compose.ui.unit.Dp,
    onPlay: () -> Unit,
) {
    // Pulse 3 times after appearance (~7.2s total), then hold at scale=1.
    val scale = remember { Animatable(1.0f) }
    LaunchedEffect(Unit) {
        repeat(3) {
            scale.animateTo(1.04f, animationSpec = tween(1200, easing = FastOutSlowInEasing))
            scale.animateTo(1.0f, animationSpec = tween(1200, easing = FastOutSlowInEasing))
        }
    }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = bottomInset),
        contentAlignment = Alignment.BottomCenter,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(120.dp)
                .background(
                    Brush.verticalGradient(
                        0.0f to Color.Transparent,
                        0.3f to UGColors.Bg0.copy(alpha = 0.6f),
                        1.0f to UGColors.Bg0,
                    )
                ),
        )
        // Suppress unused-parameter warning for `game` (kept for future
        // "Continue playing" sub-line that reads game.appId from recents).
        @Suppress("UNUSED_PARAMETER") val _g = game
        Box(
            modifier = Modifier
                .padding(bottom = 18.dp)
                .scale(scale.value)
                .shadow(
                    elevation = 18.dp,
                    shape = RoundedCornerShape(999.dp),
                    clip = false,
                    ambientColor = UGColors.Accent.copy(alpha = 0.5f),
                    spotColor = UGColors.Accent.copy(alpha = 0.5f),
                )
                .clip(RoundedCornerShape(999.dp))
                .background(UGColors.AccentGradient)
                .clickable(onClick = onPlay)
                .padding(horizontal = 28.dp, vertical = 14.dp),
        ) {
            Text(
                text = "▶ Play now",
                color = Color.Black,
                style = UGType.BodyS,
            )
        }
    }
}
