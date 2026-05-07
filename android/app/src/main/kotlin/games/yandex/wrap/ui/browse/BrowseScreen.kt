package games.yandex.wrap.ui.browse

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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import games.yandex.wrap.catalog.Game
import games.yandex.wrap.catalog.UserProfile
import games.yandex.wrap.ui.components.GenreChipRow
import games.yandex.wrap.ui.components.TileGameCard
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType
import kotlinx.coroutines.flow.distinctUntilChanged

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrowseScreen(
    viewModel: BrowseViewModel,
    profile: UserProfile,
    onGameClick: (Game) -> Unit,
    onProfileClick: () -> Unit,
) {
    val state by viewModel.state.collectAsState()
    val favoriteIds by viewModel.favoriteIds.collectAsState()
    val visible = viewModel.visibleGames(state)
    val gridState = rememberLazyGridState()
    val focusManager = LocalFocusManager.current
    val keyboardController = LocalSoftwareKeyboardController.current
    val searchFocusRequester = remember { FocusRequester() }
    val searchFocusRequest by viewModel.searchFocusRequest.collectAsState()

    LaunchedEffect(searchFocusRequest) {
        if (searchFocusRequest != 0L) {
            // Tiny delay so the LazyVerticalGrid has finished its initial
            // composition — requesting focus mid-compose can be dropped by
            // the IME on some devices.
            kotlinx.coroutines.delay(150)
            runCatching { searchFocusRequester.requestFocus() }
            keyboardController?.show()
        }
    }

    LaunchedEffect(gridState) {
        snapshotFlow {
            val info = gridState.layoutInfo
            val total = info.totalItemsCount
            val last = info.visibleItemsInfo.lastOrNull()?.index ?: -1
            Triple(total, last, info.visibleItemsInfo.size)
        }
            .distinctUntilChanged()
            .collect { (total, last, _) ->
                val current = viewModel.state.value
                if (current.mode == BrowseMode.Feed
                    && current.hasMore
                    && !current.isLoadingMore
                    && !current.isLoading
                    && total > 0
                    && last >= total - 6
                ) {
                    viewModel.loadMore()
                }
            }
    }

    LaunchedEffect(gridState) {
        snapshotFlow { gridState.isScrollInProgress }
            .distinctUntilChanged()
            .collect { scrolling ->
                if (scrolling) {
                    keyboardController?.hide()
                    focusManager.clearFocus()
                }
            }
    }

    Box(modifier = Modifier.fillMaxSize().background(UGColors.Bg0)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.statusBars),
        ) {
            BrowseTopBar(
                query = state.searchQuery,
                profile = profile,
                onQueryChange = viewModel::onSearchChange,
                onSubmit = viewModel::submitSearch,
                onProfileClick = onProfileClick,
                searchFocusRequester = searchFocusRequester,
            )
            if (state.mode == BrowseMode.Feed && state.genres.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                GenreChipRow(
                    genres = state.genres,
                    selected = state.selectedGenre,
                    onSelect = viewModel::setGenre,
                )
            }
            Spacer(Modifier.height(12.dp))
            when {
                visible.isEmpty() && state.isLoading -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) { CircularProgressIndicator(color = UGColors.TextPrimary) }
                }
                visible.isEmpty() && state.error != null -> {
                    Box(
                        modifier = Modifier.fillMaxSize().padding(24.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = state.error ?: "",
                            color = UGColors.TextSecondary,
                            style = UGType.Body,
                        )
                    }
                }
                visible.isEmpty() && state.mode == BrowseMode.Search -> {
                    Box(
                        modifier = Modifier.fillMaxSize().padding(24.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = "No games match \"${state.searchQuery}\"",
                            color = UGColors.TextSecondary,
                            style = UGType.Body,
                        )
                    }
                }
                else -> {
                    val refreshing = state.isLoading && visible.isNotEmpty()
                    PullToRefreshBox(
                        isRefreshing = refreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        LazyVerticalGrid(
                            state = gridState,
                            columns = GridCells.Adaptive(minSize = 160.dp),
                            contentPadding = PaddingValues(
                                start = 14.dp,
                                end = 14.dp,
                                top = 4.dp,
                                bottom = 96.dp,
                            ),
                            horizontalArrangement = Arrangement.spacedBy(14.dp),
                            verticalArrangement = Arrangement.spacedBy(18.dp),
                            modifier = Modifier.fillMaxSize(),
                        ) {
                            items(visible, key = { it.appId }) { game ->
                                TileGameCard(
                                    game = game,
                                    isFavorite = favoriteIds.contains(game.appId),
                                    onClick = { onGameClick(game) },
                                    onFavoriteToggle = { viewModel.toggleFavorite(game) },
                                )
                            }
                            if (state.isLoadingMore) {
                                item(span = { GridItemSpan(maxLineSpan) }) {
                                    Box(
                                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                                        contentAlignment = Alignment.Center,
                                    ) { CircularProgressIndicator(color = UGColors.TextPrimary) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun BrowseTopBar(
    query: String,
    profile: UserProfile,
    onQueryChange: (String) -> Unit,
    onSubmit: () -> Unit,
    onProfileClick: () -> Unit,
    searchFocusRequester: FocusRequester,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        OutlinedTextField(
            value = query,
            onValueChange = onQueryChange,
            modifier = Modifier.weight(1f).focusRequester(searchFocusRequester),
            placeholder = { Text("Search games", color = UGColors.TextMuted, style = UGType.BodyS) },
            leadingIcon = {
                Icon(Icons.Filled.Search, null, tint = UGColors.TextSecondary)
            },
            trailingIcon = {
                if (query.isNotEmpty()) {
                    IconButton(onClick = { onQueryChange("") }) {
                        Icon(Icons.Filled.Clear, "Clear", tint = UGColors.TextSecondary)
                    }
                }
            },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { onSubmit() }),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = UGColors.Accent,
                unfocusedBorderColor = UGColors.Divider,
                focusedContainerColor = UGColors.Surface,
                unfocusedContainerColor = UGColors.Surface,
                cursorColor = UGColors.Accent,
                focusedTextColor = UGColors.TextPrimary,
                unfocusedTextColor = UGColors.TextPrimary,
            ),
            shape = RoundedCornerShape(14.dp),
        )
        Spacer(Modifier.size(8.dp))
        BrowseAvatar(profile = profile, onClick = onProfileClick)
    }
}

@Composable
private fun BrowseAvatar(profile: UserProfile, onClick: () -> Unit) {
    val size = 38.dp
    val base = Modifier
        .size(size)
        .clip(CircleShape)
        .clickable(onClick = onClick)
    if (profile.isAuthorized && profile.avatarUrl.isNotEmpty()) {
        Box(
            modifier = base.border(
                width = if (profile.hasYaPlus) 2.dp else 0.dp,
                brush = UGColors.AccentGradient,
                shape = CircleShape,
            ),
            contentAlignment = Alignment.Center,
        ) {
            AsyncImage(
                model = profile.avatarUrl,
                contentDescription = profile.displayName.ifEmpty { profile.login },
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().clip(CircleShape),
            )
        }
    } else {
        Box(
            modifier = base.background(UGColors.Elevated),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.AccountCircle,
                contentDescription = "Profile",
                tint = UGColors.TextSecondary,
                modifier = Modifier.size(28.dp),
            )
        }
    }
}
