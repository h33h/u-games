package games.yandex.wrap.ui.detail

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.spring
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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Velocity
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
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
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.launch
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

    // Index of the currently expanded screenshot, or -1 when the
    // fullscreen viewer is dismissed. `rememberSaveable` so the
    // fullscreen state survives config changes (rotation).
    var fullscreenIndex by rememberSaveable { mutableStateOf(-1) }

    // Stretchy header: capture the pull-down overscroll at the top
    // of the LazyColumn and apply it (damped) as extra height on the
    // hero. The image inside the hero stretches to fill the new
    // bigger frame so the screen never shows bg0 above the cover.
    val listState = rememberLazyListState()
    val coroutineScope = rememberCoroutineScope()
    var pullDownPx by remember { mutableFloatStateOf(0f) }
    val canStretch by remember {
        derivedStateOf {
            listState.firstVisibleItemIndex == 0 &&
                listState.firstVisibleItemScrollOffset == 0
        }
    }
    val nestedScrollConnection = remember {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                // While there's accumulated pull, releasing (negative
                // y) drains it before letting the LazyColumn scroll.
                if (pullDownPx > 0f && available.y < 0f) {
                    val consumed = (-available.y).coerceAtMost(pullDownPx)
                    pullDownPx -= consumed
                    return Offset(0f, -consumed)
                }
                return Offset.Zero
            }

            override fun onPostScroll(
                consumed: Offset,
                available: Offset,
                source: NestedScrollSource,
            ): Offset {
                // After the LazyColumn has consumed everything it can
                // (which is nothing when at top), capture remaining
                // downward delta with 0.5 damping so the stretch feels
                // resistive instead of 1:1 with the finger.
                if (canStretch && available.y > 0f) {
                    pullDownPx += available.y * 0.5f
                    return available
                }
                return Offset.Zero
            }

            override suspend fun onPreFling(available: Velocity): Velocity {
                if (pullDownPx > 0f) {
                    val anim = Animatable(pullDownPx)
                    anim.animateTo(0f, animationSpec = spring()) { pullDownPx = value }
                    return available
                }
                return Velocity.Zero
            }
        }
    }
    val density = LocalDensity.current
    val extraDp = with(density) { pullDownPx.toDp() }

    // One continuous CTA gradient (transparent → bg0). Hits opacity
    // 100% by ~55% of its height so the home-indicator zone sits in
    // the already-opaque tail end of the same gradient — no visible
    // "solid panel" seam below the fade.
    val ctaStripHeight = 170.dp
    Box(modifier = Modifier.fillMaxSize().background(UGColors.Bg0)) {
        LazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .nestedScroll(nestedScrollConnection),
            // Bottom padding = system inset + the full CTA strip so the
            // Information block can scroll fully into view above where
            // the gradient starts becoming visible.
            contentPadding = PaddingValues(
                top = 0.dp,
                bottom = systemBarsPadding.calculateBottomPadding() + ctaStripHeight,
            ),
        ) {
            item {
                DetailHero(
                    game = game,
                    topInset = statusBarsPadding.calculateTopPadding(),
                    extraHeight = extraDp,
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
                    onScreenshotClick = { idx -> fullscreenIndex = idx },
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
        // Top controls (Back / Favorite / Share) live OUTSIDE the
        // LazyColumn so they stay anchored to the screen top while the
        // hero scrolls. They float over both the hero and any later
        // sections, with the icons' own dark glass-circle background
        // keeping them readable on top of light cover artwork.
        DetailTopBar(
            modifier = Modifier.align(Alignment.TopCenter),
            topInset = statusBarsPadding.calculateTopPadding(),
            isFavorite = state.isFavorite,
            onBack = onBack,
            onFavorite = viewModel::toggleFavorite,
            onShare = { onShare(game) },
        )

        StickyPlayCta(
            modifier = Modifier.align(Alignment.BottomCenter),
            bottomInset = systemBarsPadding.calculateBottomPadding(),
            stripHeight = ctaStripHeight,
            onPlay = { onPlay(game) },
        )
    }

    val screenshots = state.detail?.screenshots.orEmpty()
    if (fullscreenIndex in screenshots.indices) {
        ScreenshotsFullscreen(
            screenshots = screenshots,
            initialIndex = fullscreenIndex,
            onDismiss = { fullscreenIndex = -1 },
        )
    }
}

@Composable
private fun DetailHero(
    game: Game,
    topInset: androidx.compose.ui.unit.Dp,
    extraHeight: androidx.compose.ui.unit.Dp,
) {
    val haloColor = parseHexColor(game.mainColor) ?: UGColors.Accent
    val placeholder = parseHexColor(game.mainColor) ?: UGColors.Elevated
    // Hero grows by `extraHeight` when the LazyColumn is overscrolled
    // at the top — the image and gradient stretch to fill the new
    // bigger frame, keeping the screen artwork-filled instead of
    // exposing bg0 in the rubber-band gap.
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(360.dp + topInset + extraHeight)
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
    }
}

/**
 * Sticky top bar of icon buttons (Back / Favorite / Share). Hosted at
 * the screen level (BoxScope.align(TopCenter)) so it stays anchored
 * while the hero scrolls beneath it. The icons' own glass-circle
 * background keeps them readable over both cover artwork and bg0.
 */
@Composable
private fun DetailTopBar(
    modifier: Modifier = Modifier,
    topInset: androidx.compose.ui.unit.Dp,
    isFavorite: Boolean,
    onBack: () -> Unit,
    onFavorite: () -> Unit,
    onShare: () -> Unit,
) {
    Row(
        modifier = modifier
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
    onScreenshotClick: (Int) -> Unit,
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
                itemsIndexed(screenshots) { idx, url ->
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
                            )
                            .clickable { onScreenshotClick(idx) },
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
    modifier: Modifier = Modifier,
    bottomInset: androidx.compose.ui.unit.Dp,
    stripHeight: androidx.compose.ui.unit.Dp,
    onPlay: () -> Unit,
) {
    val scale = remember { Animatable(1.0f) }
    LaunchedEffect(Unit) {
        repeat(3) {
            scale.animateTo(1.04f, animationSpec = tween(1200, easing = FastOutSlowInEasing))
            scale.animateTo(1.0f, animationSpec = tween(1200, easing = FastOutSlowInEasing))
        }
    }
    // Single full-width gradient strip extending into the system inset.
    // `0.55f to Bg0` makes the fade complete just above the button so
    // the area behind the button is solid black; the rest is one
    // continuous fade. No "rectangle" seam.
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(stripHeight + bottomInset)
            .background(
                Brush.verticalGradient(
                    0.00f to Color.Transparent,
                    0.55f to UGColors.Bg0,
                    1.00f to UGColors.Bg0,
                )
            ),
    ) {
        Box(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = bottomInset + 22.dp)
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

/**
 * Full-screen pager over the JSON-LD screenshot list. Tap-to-dismiss,
 * horizontal swipe to flip between shots. Uses `/orig` size — at this
 * point bandwidth is no longer the constraint, image quality is.
 *
 * Hosted in a `Dialog` so the underlying Detail's scroll position
 * stays put when the viewer closes.
 */
@Composable
private fun ScreenshotsFullscreen(
    screenshots: List<String>,
    initialIndex: Int,
    onDismiss: () -> Unit,
) {
    val pagerState = rememberPagerState(
        initialPage = initialIndex.coerceIn(0, (screenshots.size - 1).coerceAtLeast(0)),
        pageCount = { screenshots.size },
    )
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.95f))
                .clickable(onClick = onDismiss),
            contentAlignment = Alignment.Center,
        ) {
            HorizontalPager(
                state = pagerState,
                modifier = Modifier.fillMaxSize(),
            ) { page ->
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    AsyncImage(
                        // /orig variant — full quality. The list URL
                        // already trimmed the prefix to a known shape;
                        // rewriting the suffix keeps that consistent.
                        model = upgradeToOrig(screenshots[page]),
                        contentDescription = null,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 14.dp, end = 14.dp)
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.55f))
                    .clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center,
            ) {
                Text(text = "✕", color = UGColors.TextPrimary, style = UGType.TitleM)
            }
            if (screenshots.size > 1) {
                Text(
                    text = "${pagerState.currentPage + 1} / ${screenshots.size}",
                    color = UGColors.TextSecondary,
                    style = UGType.Caption,
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(bottom = 28.dp)
                        .clip(RoundedCornerShape(999.dp))
                        .background(Color.Black.copy(alpha = 0.55f))
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                )
            }
        }
    }
}

/** Replace the `pjpg500x280` (or whatever) suffix with `orig` so the
 *  fullscreen viewer renders the full-quality screenshot. Mirrors the
 *  rewrite logic in CatalogApi.rewriteAvatarSize. */
private fun upgradeToOrig(url: String): String {
    val lastSlash = url.lastIndexOf('/')
    if (lastSlash <= 0) return url
    return url.substring(0, lastSlash + 1) + "orig"
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
