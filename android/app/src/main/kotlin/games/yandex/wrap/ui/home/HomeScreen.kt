package games.yandex.wrap.ui.home

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import games.yandex.wrap.catalog.models.Game
import games.yandex.wrap.catalog.models.UserProfile
import games.yandex.wrap.ui.components.HeroSection
import games.yandex.wrap.ui.components.Skeleton
import games.yandex.wrap.ui.components.SquareGameCard
import games.yandex.wrap.ui.components.StoryCard
import games.yandex.wrap.ui.components.WideGameCard
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType
import java.time.LocalTime

/// Editorial Home screen. Vertical scroll, no top bar — greeting / avatar /
/// search-stub all live in the first scroll item, so the Hero card flows
/// straight under the status bar without a sticky chrome edge.
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun HomeScreen(
    viewModel: HomeViewModel,
    onGameClick: (Game) -> Unit,
    onOpenBrowse: () -> Unit,
    onOpenBrowseFiltered: (String) -> Unit,
    onProfileClick: () -> Unit,
    onProfileLongPress: () -> Unit = {},
    onShareGame: (Game) -> Unit,
) {
    val state by viewModel.state.collectAsState()
    Box(modifier = Modifier.fillMaxSize().background(UGColors.Bg0)) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.statusBars),
            contentPadding = PaddingValues(top = 12.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            item("header") {
                HomeHeader(
                    profile = state.profile,
                    onProfileClick = onProfileClick,
                    onProfileLongPress = onProfileLongPress,
                )
            }
            item("search") {
                SearchStub(onClick = onOpenBrowse)
            }
            item("hero") {
                val hero = state.hero
                if (hero != null) {
                    HeroSection(
                        game = hero,
                        onPlay = { onGameClick(hero) },
                        onFavorite = { viewModel.toggleFavorite(hero) },
                        onShare = { onShareGame(hero) },
                        modifier = Modifier.padding(horizontal = 14.dp),
                    )
                } else {
                    HeroSkeleton()
                }
            }
            if (state.feedRecent.isNotEmpty()) {
                item("my_games") {
                    HomeRowSection(title = "My games", showAll = false, onSeeAll = {}) {
                        WideRow(games = state.feedRecent, onClick = onGameClick)
                    }
                }
            }
            state.spotlight?.let { spot ->
                item("spotlight") {
                    StoryCard(
                        title = spot.title,
                        subtitle = "SPOTLIGHT · ${spot.title.uppercase()}",
                        games = spot.games.take(3),
                        onClick = { onOpenBrowseFiltered(spot.title) },
                        modifier = Modifier.padding(horizontal = 14.dp),
                    )
                }
            }
            items(state.genreRows, key = { it.title }) { row ->
                HomeRowSection(
                    title = row.title,
                    showAll = true,
                    onSeeAll = { onOpenBrowseFiltered(row.title) },
                ) {
                    SquareRow(games = row.games, onClick = onGameClick)
                }
            }
            if (state.error != null && state.hero == null) {
                item("error") {
                    Text(
                        text = state.error ?: "",
                        color = UGColors.Danger,
                        style = UGType.BodyS,
                        modifier = Modifier.padding(horizontal = 14.dp),
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun HomeHeader(
    profile: UserProfile?,
    onProfileClick: () -> Unit,
    onProfileLongPress: () -> Unit,
) {
    Column(modifier = Modifier.padding(horizontal = 14.dp)) {
        Text(
            text = eyebrowFor(LocalTime.now()).uppercase(),
            color = UGColors.TextMuted,
            style = UGType.Label,
        )
        Spacer(Modifier.height(4.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = greetingFor(LocalTime.now().hour),
                color = UGColors.TextPrimary,
                style = UGType.TitleL,
                modifier = Modifier.padding(end = 8.dp),
            )
            Spacer(Modifier.weight(1f))
            ProfileAvatar(
                profile = profile,
                onClick = onProfileClick,
                onLongClick = onProfileLongPress,
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ProfileAvatar(
    profile: UserProfile?,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val size = 38.dp
    val p = profile
    if (p?.isAuthorized == true && p.avatarUrl.isNotEmpty()) {
        Box(
            modifier = Modifier
                .size(size)
                .clip(CircleShape)
                .border(
                    width = if (p.hasYaPlus) 2.dp else 0.dp,
                    brush = UGColors.AccentGradient,
                    shape = CircleShape,
                )
                .combinedClickable(onClick = onClick, onLongClick = onLongClick),
            contentAlignment = Alignment.Center,
        ) {
            AsyncImage(
                model = p.avatarUrl,
                contentDescription = p.displayName.ifEmpty { p.login },
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().clip(CircleShape),
            )
        }
    } else {
        Box(
            modifier = Modifier
                .size(size)
                .clip(CircleShape)
                .background(UGColors.Elevated)
                .combinedClickable(onClick = onClick, onLongClick = onLongClick),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.AccountCircle,
                contentDescription = "Sign in",
                tint = UGColors.TextSecondary,
                modifier = Modifier.size(28.dp),
            )
        }
    }
}

@Composable
private fun SearchStub(onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .padding(horizontal = 14.dp)
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(UGColors.Surface)
            .border(1.dp, UGColors.Divider, RoundedCornerShape(14.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            Icons.Filled.Search,
            contentDescription = null,
            tint = UGColors.TextMuted,
            modifier = Modifier.size(18.dp),
        )
        Spacer(Modifier.size(10.dp))
        Text(text = "Search games", color = UGColors.TextMuted, style = UGType.BodyS)
    }
}

@Composable
private fun HomeRowSection(
    title: String,
    showAll: Boolean,
    onSeeAll: () -> Unit,
    content: @Composable () -> Unit,
) {
    Column {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp).fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(text = title, color = UGColors.TextPrimary, style = UGType.TitleM)
            if (showAll) {
                Spacer(Modifier.weight(1f))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.clickable(onClick = onSeeAll),
                ) {
                    Text(text = "See all", color = UGColors.TextSecondary, style = UGType.BodyS)
                    Icon(
                        Icons.Filled.ChevronRight,
                        contentDescription = null,
                        tint = UGColors.TextSecondary,
                        modifier = Modifier.size(16.dp),
                    )
                }
            }
        }
        Spacer(Modifier.height(10.dp))
        content()
    }
}

@Composable
private fun WideRow(games: List<Game>, onClick: (Game) -> Unit) {
    // Per-item vertical padding makes each item's reported size
    // include the mainColor shadow halo. 20dp leaves clear room for
    // the 12dp shadow plus anti-alias bleed; previous values (14, 16)
    // proved too tight — LazyRow's container clip kept cropping.
    LazyRow(
        contentPadding = PaddingValues(horizontal = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(games, key = { it.appId }) { g ->
            Box(modifier = Modifier.padding(vertical = 20.dp)) {
                WideGameCard(game = g, onClick = { onClick(g) })
            }
        }
    }
}

@Composable
private fun SquareRow(games: List<Game>, onClick: (Game) -> Unit) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(games, key = { it.appId }) { g ->
            Box(modifier = Modifier.padding(vertical = 20.dp)) {
                SquareGameCard(game = g, onClick = { onClick(g) })
            }
        }
    }
}

@Composable
private fun HeroSkeleton() {
    Box(modifier = Modifier.padding(horizontal = 14.dp).fillMaxWidth()) {
        Skeleton(
            modifier = Modifier.fillMaxWidth().height(300.dp),
            cornerRadius = 22.dp,
        )
        // Slight tint hint of accent so the skeleton doesn't feel pure dead.
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(300.dp)
                .clip(RoundedCornerShape(22.dp))
                .background(Color.Transparent),
        )
    }
}

private fun greetingFor(hour: Int): String = when {
    hour < 12 -> "Good morning"
    hour < 18 -> "Good afternoon"
    else -> "Good evening"
}

private fun eyebrowFor(@Suppress("UNUSED_PARAMETER") time: LocalTime): String {
    val day = java.time.LocalDate.now().dayOfWeek.name.lowercase()
        .replaceFirstChar { it.titlecase() }
    return "$day · Top picks"
}
