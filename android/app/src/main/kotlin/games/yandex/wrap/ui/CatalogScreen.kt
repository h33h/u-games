package games.yandex.wrap.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import games.yandex.wrap.catalog.CatalogRepository
import games.yandex.wrap.catalog.Game
import kotlinx.coroutines.flow.flowOf

@Composable
fun CatalogScreen(
    repository: CatalogRepository,
    onGameClick: (Game) -> Unit,
) {
    val state by remember { repository.feed() }.collectAsState(initial = Result.success(emptyList()))

    val games = state.getOrNull().orEmpty()
    val error = state.exceptionOrNull()

    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        when {
            games.isEmpty() && error == null -> {
                CircularProgressIndicator(
                    modifier = Modifier.align(Alignment.Center),
                    color = Color.White,
                )
            }
            games.isEmpty() && error != null -> {
                Column(
                    modifier = Modifier.align(Alignment.Center).padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        text = error.message ?: "Couldn't load catalog",
                        color = Color.White,
                    )
                }
            }
            else -> CatalogGrid(games = games, onClick = onGameClick)
        }
    }
}

@Composable
private fun CatalogGrid(games: List<Game>, onClick: (Game) -> Unit) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(games, key = { it.appId }) { game ->
            GameCard(game = game, onClick = { onClick(game) })
        }
    }
}

@Composable
private fun GameCard(game: Game, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0xFF1A1A1A))
            .clickable(onClick = onClick)
            .padding(8.dp),
    ) {
        AsyncImage(
            model = game.coverUrl,
            contentDescription = game.title,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(16f / 9f)
                .clip(RoundedCornerShape(8.dp)),
        )
        androidx.compose.foundation.layout.Spacer(Modifier.padding(top = 6.dp))
        Text(
            text = game.title,
            color = Color.White,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            maxLines = 2,
        )
        if (game.ratingCount > 0) {
            Text(
                text = "★ ${"%.1f".format(game.rating)}",
                color = Color(0xFFFFC700),
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}
