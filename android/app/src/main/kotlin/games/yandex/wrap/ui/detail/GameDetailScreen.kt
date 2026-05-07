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
import games.yandex.wrap.catalog.AppDetail
import games.yandex.wrap.catalog.Game
import games.yandex.wrap.ui.components.Skeleton
import games.yandex.wrap.ui.components.TileGameCard
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType
import games.yandex.wrap.ui.theme.parseHexColor
import java.util.Locale

/**
 * Phase 3 push screen between any catalog card and the WebView. Every
 * field is real data from the feed item or JSON-LD; nothing is
 * fabricated and no two sections show the same fact twice.
 *
 * Sections (top to bottom):
 *  1. Hero (360dp): hi-res cover + mainColor halo + sticky ← / ♥ / ↗.
 *  2. Title block — eyebrow (genre · year), DisplayXL title, "by
 *     {developer}" line, chips (rating · count, age rating) — chips
 *     only render fields that exist; no fakes.
 *  3. About paragraph — JSON-LD `mainEntityOfPage.description`.
 *  4. Screenshots — JSON-LD `screenshot[]` rewritten to pjpg500x280.
 *  5. More like this — `similar_games` endpoint.
 *  6. Information — key/value rows for the long-tail metadata that
 *     doesn't fit a chip (full genre list, languages, developer
 *     again-but-formatted, release date). Only fields with data render.
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
            item {
                TitleBlock(
                    game = game,
                    year = yearFromIso(state.detail?.datePublished),
                    author = pickAuthor(game, state.detail),
                )
            }
            item { Spacer(Modifier.height(24.dp)) }
            item {
                AboutSection(
                    description = state.detail?.description,
                    isLoading = state.isLoadingDetail,
                )
            }
            item {
                ScreenshotsRow(
                    screenshots = state.detail?.screenshots.orEmpty(),
                    isLoading = state.isLoadingDetail,
                    haloHex = game.mainColor,
                )
            }
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
            item { Spacer(Modifier.height(24.dp)) }
            item { InformationBlock(game = game, detail = state.detail) }
        }
        StickyPlayCta(
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
            // Hero is 360dp tall — `pjpg250x140` looked like a postage
            // stamp. `pjpg1280x720` is the next-largest pre-rendered
            // size on Yandex's avatars storage and weighs ~120 KB.
            // Falls back to the feed-cover URL if no prefix is available
            // (e.g. game decoded from the favorites cache).
            model = game.coverUrl("pjpg1280x720"),
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
private fun TitleBlock(game: Game, year: String?, author: String?) {
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp)) {
        // Eyebrow combines anything we have: first genre + release year.
        // Both fields are honest data — no hardcoded suffix.
        val eyebrowText = listOfNotNull(
            game.categories.firstOrNull()?.uppercase(),
            year,
        ).joinToString(" · ")
        if (eyebrowText.isNotEmpty()) {
            Text(text = eyebrowText, color = UGColors.TextMuted, style = UGType.Label)
            Spacer(Modifier.height(8.dp))
        }
        Text(
            text = game.title,
            color = UGColors.TextPrimary,
            style = UGType.DisplayXL,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
        )
        if (!author.isNullOrBlank()) {
            Spacer(Modifier.height(8.dp))
            Text(
                text = "by $author",
                color = UGColors.TextSecondary,
                style = UGType.BodyS,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        // Chips: only fields that have data. No fake "No ads" claim.
        val chips = buildList {
            if (game.rating > 0f) {
                add(buildString {
                    append("★ %.1f".format(Locale.US, game.rating))
                    if (game.ratingCount > 0) {
                        append(" · ")
                        append(formatCount(game.ratingCount))
                    }
                })
            } else if (game.ratingCount > 0) {
                add("${formatCount(game.ratingCount)} ratings")
            }
            if (!game.ageRating.isNullOrBlank()) add(game.ageRating)
        }
        if (chips.isNotEmpty()) {
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                chips.forEach { chip ->
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(999.dp))
                            .background(Color.White.copy(alpha = 0.08f))
                            .padding(horizontal = 9.dp, vertical = 5.dp),
                    ) {
                        Text(
                            text = chip,
                            color = UGColors.TextSecondary,
                            style = UGType.Caption,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun AboutSection(description: String?, isLoading: Boolean) {
    when {
        isLoading && description == null -> Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp)) {
            Text(text = "ABOUT", color = UGColors.TextMuted, style = UGType.Label)
            Spacer(Modifier.height(10.dp))
            repeat(3) {
                Skeleton(modifier = Modifier.fillMaxWidth().height(12.dp), cornerRadius = 4.dp)
                Spacer(Modifier.height(8.dp))
            }
            Spacer(Modifier.height(12.dp))
        }
        !description.isNullOrBlank() -> Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp)) {
            Text(text = "ABOUT", color = UGColors.TextMuted, style = UGType.Label)
            Spacer(Modifier.height(10.dp))
            Text(text = description, color = UGColors.TextSecondary, style = UGType.Body)
            Spacer(Modifier.height(20.dp))
        }
        else -> Spacer(Modifier.height(0.dp))  // collapse silently
    }
}

@Composable
private fun ScreenshotsRow(
    screenshots: List<String>,
    isLoading: Boolean,
    haloHex: String?,
) {
    when {
        isLoading && screenshots.isEmpty() -> Column {
            Text(
                text = "SCREENSHOTS",
                color = UGColors.TextMuted,
                style = UGType.Label,
                modifier = Modifier.padding(horizontal = 18.dp),
            )
            Spacer(Modifier.height(10.dp))
            LazyRow(
                contentPadding = PaddingValues(horizontal = 18.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(3) {
                    Skeleton(modifier = Modifier.width(220.dp).height(124.dp), cornerRadius = 16.dp)
                }
            }
        }
        screenshots.isNotEmpty() -> Column {
            Text(
                text = "SCREENSHOTS",
                color = UGColors.TextMuted,
                style = UGType.Label,
                modifier = Modifier.padding(horizontal = 18.dp),
            )
            Spacer(Modifier.height(10.dp))
            val halo = parseHexColor(haloHex) ?: UGColors.Accent
            LazyRow(
                contentPadding = PaddingValues(horizontal = 18.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(screenshots) { url ->
                    Box(
                        modifier = Modifier
                            .width(220.dp)
                            .height(124.dp)
                            .shadow(
                                elevation = 12.dp,
                                shape = RoundedCornerShape(16.dp),
                                clip = false,
                                ambientColor = halo.copy(alpha = UGColors.HaloAlpha),
                                spotColor = halo.copy(alpha = UGColors.HaloAlpha),
                            )
                            .clip(RoundedCornerShape(16.dp))
                            .background(UGColors.Elevated)
                            .border(
                                width = 1.dp,
                                color = halo.copy(alpha = UGColors.HaloBorderAlpha),
                                shape = RoundedCornerShape(16.dp),
                            ),
                    ) {
                        AsyncImage(
                            model = url,
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize(),
                        )
                    }
                }
            }
        }
        else -> Spacer(Modifier.height(0.dp))
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
                Skeleton(modifier = Modifier.width(160.dp).height(140.dp), cornerRadius = 16.dp)
            }
        }
        error != null && similar.isEmpty() -> Text(
            text = "Couldn't load related games",
            color = UGColors.TextMuted,
            style = UGType.BodyS,
            modifier = Modifier.padding(horizontal = 18.dp),
        )
        similar.isEmpty() -> {}
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
private fun InformationBlock(game: Game, detail: AppDetail?) {
    // Build the rows from real data only — every empty source collapses
    // its own row so the section silently shrinks instead of showing
    // "—" placeholders. The full genre list goes here (the eyebrow only
    // had room for the first genre); language list is JSON-LD-only;
    // developer is the catalog's value, formatted as a row instead of
    // floating loose under the title.
    val author = pickAuthor(game, detail)
    val rows = buildList {
        if (!author.isNullOrBlank()) add("Developer" to author)
        formatReleaseDate(detail?.datePublished)?.let { add("Released" to it) }
        val genres = pickGenres(game, detail)
        if (genres.isNotEmpty()) add("Genres" to genres.joinToString(" · "))
        if (!detail?.languages.isNullOrEmpty()) {
            add("Languages" to detail!!.languages.map { it.uppercase(Locale.US) }.joinToString(", "))
        }
    }
    if (rows.isEmpty()) return
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp)) {
        Text(text = "INFORMATION", color = UGColors.TextMuted, style = UGType.Label)
        Spacer(Modifier.height(10.dp))
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(14.dp))
                .background(UGColors.Surface),
        ) {
            rows.forEachIndexed { idx, (label, value) ->
                if (idx > 0) {
                    Box(modifier = Modifier.fillMaxWidth().height(1.dp).background(UGColors.Divider))
                }
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(text = label, color = UGColors.TextMuted, style = UGType.BodyS, modifier = Modifier.width(110.dp))
                    Text(
                        text = value,
                        color = UGColors.TextPrimary,
                        style = UGType.BodyS,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}

@Composable
private fun StickyPlayCta(
    bottomInset: androidx.compose.ui.unit.Dp,
    onPlay: () -> Unit,
) {
    val scale = remember { Animatable(1.0f) }
    LaunchedEffect(Unit) {
        repeat(3) {
            scale.animateTo(1.04f, animationSpec = tween(1200, easing = FastOutSlowInEasing))
            scale.animateTo(1.0f, animationSpec = tween(1200, easing = FastOutSlowInEasing))
        }
    }
    Box(
        modifier = Modifier.fillMaxWidth().padding(bottom = bottomInset),
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
            Text(text = "▶ Play now", color = Color.Black, style = UGType.BodyS)
        }
    }
}

// --- helpers ---------------------------------------------------------

/** Extract just the year from `datePublished`. JSON-LD allows full
 *  ISO-8601 timestamps as well as bare `YYYY` strings. */
private fun yearFromIso(iso: String?): String? {
    if (iso.isNullOrBlank()) return null
    val first4 = iso.take(4)
    return if (first4.length == 4 && first4.all { it.isDigit() }) first4 else null
}

/** Pretty `Mon DD, YYYY` from JSON-LD `datePublished`. Drops the time
 *  portion to match what the App Store shows. Falls back to year-only
 *  when the date doesn't have a month/day. */
private fun formatReleaseDate(iso: String?): String? {
    if (iso.isNullOrBlank()) return null
    if (iso.length < 10) return yearFromIso(iso)
    val (y, m, d) = try {
        Triple(iso.substring(0, 4).toInt(), iso.substring(5, 7).toInt(), iso.substring(8, 10).toInt())
    } catch (_: Throwable) {
        return yearFromIso(iso)
    }
    val months = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
    val month = months.getOrNull(m - 1) ?: return yearFromIso(iso)
    return "$month %02d, %d".format(d, y)
}

/** Prefer JSON-LD `author.name` when present (sometimes formatted
 *  better — e.g. with proper capitalization), fall back to the catalog
 *  feed's `developer.name`. Both fields point at the same studio. */
private fun pickAuthor(game: Game, detail: AppDetail?): String? {
    detail?.author?.takeIf { it.isNotBlank() }?.let { return it }
    return game.developer.takeIf { it.isNotBlank() }
}

/** JSON-LD `genre[]` is the richer source (multiple values, includes
 *  audience-targeted genres like "For boys"). Catalog feed's
 *  `categoriesNames` is the fallback when JSON-LD didn't provide one. */
private fun pickGenres(game: Game, detail: AppDetail?): List<String> {
    val ld = detail?.genres.orEmpty().filter { it.isNotBlank() }
    if (ld.isNotEmpty()) return ld
    return game.categories.filter { it.isNotBlank() }
}

/** Compact rating-count formatter: 12340 → "12.3K", 1_240_000 → "1.2M",
 *  3000 → "3K" (no trailing ".0"). */
private fun formatCount(n: Int): String = when {
    n >= 1_000_000 -> compact(n / 1_000_000.0, "M")
    n >= 1_000 -> compact(n / 1_000.0, "K")
    else -> n.toString()
}

private fun compact(v: Double, suffix: String): String {
    val rounded = (v * 10).toInt() / 10.0
    return if (rounded == rounded.toInt().toDouble()) "${rounded.toInt()}$suffix"
    else "%.1f$suffix".format(Locale.US, rounded)
}
