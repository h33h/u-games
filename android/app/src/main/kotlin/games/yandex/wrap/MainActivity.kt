package games.yandex.wrap

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import games.yandex.wrap.catalog.Game
import games.yandex.wrap.ui.AuthScreen
import games.yandex.wrap.ui.GameScreen
import games.yandex.wrap.ui.LogsScreen
import games.yandex.wrap.ui.TabContainer
import games.yandex.wrap.ui.TabPushed
import games.yandex.wrap.ui.browse.BrowseScreen
import games.yandex.wrap.ui.browse.BrowseViewModel
import games.yandex.wrap.ui.detail.GameDetailScreen
import games.yandex.wrap.ui.detail.GameDetailViewModel
import games.yandex.wrap.ui.favorites.FavoritesScreen
import games.yandex.wrap.ui.home.HomeScreen
import games.yandex.wrap.ui.home.HomeViewModel
import games.yandex.wrap.ui.profile.AboutScreen
import games.yandex.wrap.ui.profile.ProfileScreen
import games.yandex.wrap.ui.profile.ProfileViewModel
import games.yandex.wrap.ui.theme.UGamesTheme
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private val app: UGamesApplication
        get() = application as UGamesApplication

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val factory = viewModelFactory {
            initializer {
                HomeViewModel(
                    app.catalogRepository,
                    app.favoritesRepository,
                    app.profileRepository,
                )
            }
            initializer { BrowseViewModel(app.catalogRepository, app.favoritesRepository) }
            initializer { ProfileViewModel(app.profileRepository) }
        }
        val provider = ViewModelProvider(this, factory)
        val homeVm = provider[HomeViewModel::class.java]
        val browseVm = provider[BrowseViewModel::class.java]
        val profileVm = provider[ProfileViewModel::class.java]

        // Deep-link bypasses the Detail screen because we don't have a
        // full Game object on cold start (only the appId). The user lands
        // straight in the WebView, matching the link's "open the game"
        // intent.
        val deepLink: TabPushed = parseDeepLink(intent)
            ?.let { TabPushed.Game(appId = it, title = "") }
            ?: TabPushed.None

        // Phase 3: card clicks land on GameDetail first; Detail's "Play
        // now" is what pushes the WebView. Yandex maintains recents
        // server-side per profile, so no local store update here.
        val openGame: (Game, (TabPushed) -> Unit) -> Unit = { game, push ->
            push(TabPushed.GameDetail(game))
        }

        val openShare: (Game) -> Unit = { game ->
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_SUBJECT, game.title)
                putExtra(Intent.EXTRA_TEXT, game.playUrl)
            }
            startActivity(Intent.createChooser(intent, "Share game"))
        }

        setContent {
            UGamesTheme {
                val favorites by homeVm.favorites.collectAsState()
                TabContainer(
                    initialTab = "home",
                    initialPushed = deepLink,
                    home = { push, switchTab ->
                        HomeScreen(
                            viewModel = homeVm,
                            onGameClick = { game -> openGame(game, push) },
                            onOpenBrowse = {
                                browseVm.requestSearchFocus()
                                switchTab("browse")
                            },
                            onOpenBrowseFiltered = { genre ->
                                browseVm.setCategoryByName(genre)
                                switchTab("browse")
                            },
                            onProfileClick = { push(TabPushed.Profile) },
                            onProfileLongPress = { push(TabPushed.Logs) },
                            onShareGame = openShare,
                        )
                    },
                    browse = { push, _ ->
                        BrowseScreen(
                            viewModel = browseVm,
                            onGameClick = { game -> openGame(game, push) },
                        )
                    },
                    favorites = { push, switchTab ->
                        FavoritesScreen(
                            games = favorites,
                            onGameClick = { game -> openGame(game, push) },
                            onToggleFavorite = { game -> homeVm.toggleFavorite(game) },
                            onBrowse = { switchTab("browse") },
                        )
                    },
                    pushedHost = { pushed, push, onPop, replace ->
                        when (pushed) {
                            is TabPushed.GameDetail -> {
                                // Fresh VM keyed on the game so navigating
                                // Detail(A) → Similar tile → Detail(B) gets
                                // a clean state and a new similar fetch.
                                val detailVm = remember(pushed.game.appId) {
                                    GameDetailViewModel(
                                        catalogRepository = app.catalogRepository,
                                        favoritesRepository = app.favoritesRepository,
                                        initialGame = pushed.game,
                                    )
                                }
                                GameDetailScreen(
                                    viewModel = detailVm,
                                    onBack = onPop,
                                    onPlay = { game ->
                                        push(TabPushed.Game(game.appId, game.title))
                                    },
                                    onShare = openShare,
                                    onSimilarClick = { game ->
                                        push(TabPushed.GameDetail(game))
                                    },
                                    onSimilarFavoriteToggle = { game ->
                                        // Repository toggle bypasses the
                                        // detail VM so any tab that
                                        // observes favoriteIds (Browse,
                                        // Favorites grid, Home favorites
                                        // row) updates immediately.
                                        lifecycleScope.launch {
                                            runCatching {
                                                app.favoritesRepository.toggleFavorite(game)
                                            }
                                        }
                                    },
                                )
                            }
                            is TabPushed.Game -> GameScreen(
                                appId = pushed.appId,
                                title = pushed.title,
                                scripts = app.injectedScripts,
                                blockList = app.blockList,
                                config = app.appConfig,
                                onBack = {
                                    // Yandex updates server-side
                                    // recentGames on the play session —
                                    // refresh Home so the just-played
                                    // game appears in Recently played.
                                    homeVm.onGameSessionEnded()
                                    onPop()
                                },
                            )
                            TabPushed.Auth -> AuthScreen(config = app.appConfig, onClose = {
                                profileVm.refresh()
                                homeVm.refresh()
                                onPop()
                            })
                            TabPushed.Logs -> LogsScreen(onClose = onPop)
                            TabPushed.About -> AboutScreen(onBack = onPop)
                            TabPushed.Profile -> ProfileScreen(
                                viewModel = profileVm,
                                onBack = onPop,
                                onLoginClick = { replace(TabPushed.Auth) },
                                onLogsClick = { replace(TabPushed.Logs) },
                                onAboutClick = { replace(TabPushed.About) },
                            )
                            TabPushed.None -> {}
                        }
                    },
                )
            }
        }
    }
}

/// Parse ugames://app/<id> deep links. Returns the appId if the URI matches,
/// null otherwise (so callers fall back to the default Home tab). Tolerant
/// of `https://yandex.com/games/app/<id>` intents in case Android claims
/// the URL via auto-verify even though we don't ship Digital Asset Links.
private fun parseDeepLink(intent: Intent?): Long? {
    val uri: Uri = intent?.data ?: return null
    val scheme = uri.scheme?.lowercase() ?: return null
    val pathSegments = uri.pathSegments
    return when (scheme) {
        "ugames" -> {
            if (uri.host == "app") pathSegments.firstOrNull()?.toLongOrNull() else null
        }
        "https", "http" -> {
            if (uri.host in setOf("yandex.com", "yandex.ru")) {
                val idx = pathSegments.indexOf("app")
                if (idx >= 0 && idx + 1 < pathSegments.size) pathSegments[idx + 1].toLongOrNull() else null
            } else null
        }
        else -> null
    }
}
