package games.yandex.wrap.ui.favorites

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import games.yandex.wrap.catalog.Game
import games.yandex.wrap.ui.components.EmptyState
import games.yandex.wrap.ui.components.TileGameCard
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType

/**
 * Favorites tab. Reads from [games] supplied by the caller (a Flow that the
 * caller has already collected via collectAsState). When empty: an
 * [EmptyState] with a CTA that hops to Browse. Otherwise: an `Adaptive(160dp)`
 * grid of [TileGameCard].
 */
@Composable
fun FavoritesScreen(
    games: List<Game>,
    onGameClick: (Game) -> Unit,
    onToggleFavorite: (Game) -> Unit,
    onBrowse: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(UGColors.Bg0)
            .windowInsetsPadding(WindowInsets.statusBars),
    ) {
        if (games.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                EmptyState(
                    icon = Icons.Filled.FavoriteBorder,
                    title = "No favorites yet",
                    body = "Tap ♥ on any game to save it.",
                    ctaLabel = "Browse games",
                    onCta = onBrowse,
                )
            }
        } else {
            Column(modifier = Modifier.fillMaxSize()) {
                Spacer(Modifier.height(12.dp))
                Text(
                    text = "Favorites · ${games.size}",
                    color = UGColors.TextPrimary,
                    style = UGType.TitleM,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                )
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(minSize = 160.dp),
                    contentPadding = PaddingValues(
                        start = 12.dp,
                        end = 12.dp,
                        top = 8.dp,
                        bottom = 96.dp,
                    ),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    items(games, key = { it.appId }) { game ->
                        TileGameCard(
                            game = game,
                            isFavorite = true,
                            onClick = { onGameClick(game) },
                            onFavoriteToggle = { onToggleFavorite(game) },
                        )
                    }
                }
            }
        }
    }
}
