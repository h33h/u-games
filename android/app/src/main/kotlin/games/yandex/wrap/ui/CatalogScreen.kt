package games.yandex.wrap.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items as lazyRowItems
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
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import games.yandex.wrap.catalog.Game
import games.yandex.wrap.catalog.UserProfile
import kotlinx.coroutines.flow.distinctUntilChanged

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CatalogScreen(
    viewModel: CatalogViewModel,
    onGameClick: (Game) -> Unit,
    onLoginClick: () -> Unit,
    onLogsRequest: () -> Unit = {},
) {
    val state by viewModel.state.collectAsState()
    val recent by viewModel.recent.collectAsState()
    val favorites by viewModel.favorites.collectAsState()
    val favoriteIds by viewModel.favoriteIds.collectAsState()
    val gridState = rememberLazyGridState()
    val focusManager = LocalFocusManager.current
    val keyboardController = LocalSoftwareKeyboardController.current
    var profileSheetVisible by remember { mutableStateOf(false) }

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
                if (current.mode == Mode.Feed
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

    // Dismiss keyboard once the user starts scrolling the grid.
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

    Box(modifier = Modifier
        .fillMaxSize()
        .background(Color.Black)
    ) {
        Column(modifier = Modifier
            .fillMaxSize()
            .windowInsetsPadding(WindowInsets.statusBars)
        ) {
            CatalogTopBar(
                query = state.searchQuery,
                profile = state.profile,
                onQueryChange = viewModel::onSearchChange,
                onSubmit = viewModel::submitSearch,
                onProfileClick = {
                    if (state.profile.isAuthorized) profileSheetVisible = true else onLoginClick()
                },
                onProfileLongPress = onLogsRequest,
            )

            when {
                state.games.isEmpty() && state.isLoading -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) { CircularProgressIndicator(color = Color.White) }
                }
                state.games.isEmpty() && state.error != null -> {
                    Box(
                        modifier = Modifier.fillMaxSize().padding(24.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(state.error ?: "", color = Color.White)
                            Spacer(Modifier.height(16.dp))
                            TextButton(onClick = viewModel::refreshFeed) {
                                Text("Retry", color = Color(0xFFFFC700))
                            }
                        }
                    }
                }
                state.games.isEmpty() && state.mode == Mode.Search -> {
                    Box(
                        modifier = Modifier.fillMaxSize().padding(24.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("No games match \"${state.searchQuery}\"", color = Color.White)
                    }
                }
                else -> {
                    val refreshing = state.isLoading && state.games.isNotEmpty()
                    PullToRefreshBox(
                        isRefreshing = refreshing,
                        onRefresh = { viewModel.refreshFeed() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                    LazyVerticalGrid(
                        state = gridState,
                        // Adaptive: at least 160dp wide cards. 360dp phones → 2,
                        // 600dp tablets → 3, 840dp+ landscape → 4-5.
                        columns = GridCells.Adaptive(minSize = 160.dp),
                        contentPadding = PaddingValues(start = 12.dp, end = 12.dp, top = 12.dp, bottom = 96.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        if (favorites.isNotEmpty() && state.mode == Mode.Feed) {
                            item(span = { GridItemSpan(maxLineSpan) }) {
                                HorizontalGameRow(
                                    title = "Favorites",
                                    games = favorites,
                                    onClick = onGameClick,
                                )
                            }
                        }
                        if (recent.isNotEmpty() && state.mode == Mode.Feed) {
                            item(span = { GridItemSpan(maxLineSpan) }) {
                                HorizontalGameRow(
                                    title = "Recently played",
                                    games = recent,
                                    onClick = onGameClick,
                                )
                            }
                        }
                        items(state.games, key = { it.appId }) { game ->
                            GameCard(
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
                                    contentAlignment = Alignment.Center
                                ) { CircularProgressIndicator(color = Color.White) }
                            }
                        }
                    }
                    }
                }
            }
        }

        if (profileSheetVisible) {
            ProfileSheet(
                profile = state.profile,
                onSignOut = {
                    profileSheetVisible = false
                    viewModel.signOut()
                },
                onDismiss = { profileSheetVisible = false },
            )
        }
    }
}

@Composable
private fun CatalogTopBar(
    query: String,
    profile: UserProfile,
    onQueryChange: (String) -> Unit,
    onSubmit: () -> Unit,
    onProfileClick: () -> Unit,
    onProfileLongPress: () -> Unit = {},
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
            modifier = Modifier.weight(1f),
            placeholder = { Text("Search games", color = Color(0xFF888888)) },
            leadingIcon = { Icon(Icons.Default.Search, null, tint = Color(0xFFAAAAAA)) },
            trailingIcon = {
                if (query.isNotEmpty()) {
                    IconButton(onClick = { onQueryChange("") }) {
                        Icon(Icons.Default.Clear, "Clear", tint = Color(0xFFAAAAAA))
                    }
                }
            },
            singleLine = true,
            textStyle = TextStyle(color = Color.White, fontSize = 16.sp),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { onSubmit() }),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = Color(0xFFFFC700),
                unfocusedBorderColor = Color(0xFF444444),
                focusedContainerColor = Color(0xFF1A1A1A),
                unfocusedContainerColor = Color(0xFF1A1A1A),
                cursorColor = Color(0xFFFFC700),
            ),
            shape = RoundedCornerShape(12.dp),
        )
        Spacer(Modifier.size(8.dp))
        ProfileButton(
            profile = profile,
            onClick = onProfileClick,
            onLongClick = onProfileLongPress,
        )
    }
}

/**
 * Long-press on the profile avatar opens the in-app diagnostic Logs view.
 * Useful for debugging stuck game launches, auth, and orientation issues
 * without a USB cable. Mirrors the iOS `.onLongPressGesture` on the topbar —
 * Compose dispatches gestures top-down so the parent Row can't swallow
 * long-press without breaking the OutlinedTextField focus, hence we attach
 * to the profile button area.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ProfileButton(
    profile: UserProfile,
    onClick: () -> Unit,
    onLongClick: () -> Unit = {},
) {
    if (profile.isAuthorized && profile.avatarUrl.isNotEmpty()) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .combinedClickable(onClick = onClick, onLongClick = onLongClick),
            contentAlignment = Alignment.Center,
        ) {
            AsyncImage(
                model = profile.avatarUrl,
                contentDescription = profile.displayName.ifEmpty { profile.login },
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
    } else {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .combinedClickable(onClick = onClick, onLongClick = onLongClick),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Default.AccountCircle,
                contentDescription = "Login",
                tint = Color.White,
                modifier = Modifier.size(34.dp),
            )
        }
    }
}

@Composable
private fun HorizontalGameRow(title: String, games: List<Game>, onClick: (Game) -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
    ) {
        Text(
            text = title,
            color = Color.White,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(start = 4.dp, bottom = 8.dp),
        )
        LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            lazyRowItems(games, key = { it.appId }) { game ->
                Column(
                    modifier = Modifier
                        .width(100.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .clickable { onClick(game) },
                ) {
                    AsyncImage(
                        model = game.iconUrl.ifEmpty { game.coverUrl },
                        contentDescription = game.title,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .size(100.dp)
                            .clip(RoundedCornerShape(12.dp)),
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = game.title,
                        color = Color.White,
                        style = MaterialTheme.typography.bodySmall,
                        maxLines = 2,
                    )
                }
            }
        }
    }
}

@Composable
private fun GameCard(
    game: Game,
    isFavorite: Boolean,
    onClick: () -> Unit,
    onFavoriteToggle: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0xFF1A1A1A))
            .clickable(onClick = onClick)
            .padding(8.dp),
    ) {
        Box(modifier = Modifier.fillMaxWidth()) {
            AsyncImage(
                model = game.coverUrl,
                contentDescription = game.title,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(16f / 9f)
                    .clip(RoundedCornerShape(8.dp)),
            )
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(6.dp)
                    .size(30.dp)
                    .clip(CircleShape)
                    .background(Color(0x8C000000))
                    .clickable(onClick = onFavoriteToggle),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = if (isFavorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                    contentDescription = if (isFavorite) "Remove from favorites" else "Add to favorites",
                    tint = if (isFavorite) Color(0xFFFF4D6A) else Color.White,
                    modifier = Modifier.size(16.dp),
                )
            }
        }
        Spacer(Modifier.height(6.dp))
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProfileSheet(
    profile: UserProfile,
    onSignOut: () -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState()
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color(0xFF111111),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (profile.avatarUrl.isNotEmpty()) {
                AsyncImage(
                    model = profile.avatarUrl,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.size(72.dp).clip(CircleShape),
                )
            } else {
                Icon(
                    Icons.Default.AccountCircle,
                    contentDescription = null,
                    tint = Color(0xFF555555),
                    modifier = Modifier.size(72.dp),
                )
            }
            Spacer(Modifier.height(12.dp))
            Text(
                text = profile.displayName.ifEmpty { profile.login },
                color = Color.White,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            if (profile.login.isNotEmpty() && profile.displayName != profile.login) {
                Text(
                    text = profile.login,
                    color = Color(0xFF888888),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            if (profile.hasYaPlus) {
                Spacer(Modifier.height(8.dp))
                Text(
                    text = "Yandex Plus",
                    color = Color(0xFFFFC700),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(Color(0x33FFC700))
                        .padding(horizontal = 10.dp, vertical = 4.dp),
                )
            }
            Spacer(Modifier.height(24.dp))
            Button(
                onClick = onSignOut,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFF2A1414),
                    contentColor = Color(0xFFFF6B6B),
                ),
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
            ) {
                Icon(Icons.AutoMirrored.Filled.ExitToApp, contentDescription = null)
                Spacer(Modifier.size(8.dp))
                Text("Sign out")
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}
