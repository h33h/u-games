package games.yandex.wrap

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
            initializer { HomeViewModel(app.catalogRepository) }
            initializer { BrowseViewModel(app.catalogRepository) }
            initializer { ProfileViewModel(app.catalogRepository) }
        }
        val provider = ViewModelProvider(this, factory)
        val homeVm = provider[HomeViewModel::class.java]
        val browseVm = provider[BrowseViewModel::class.java]
        val profileVm = provider[ProfileViewModel::class.java]

        val deepLink: TabPushed = parseDeepLink(intent)
            ?.let { TabPushed.Game(appId = it, title = "") }
            ?: TabPushed.None

        val openGame: (Game, (TabPushed) -> Unit) -> Unit = { game, push ->
            lifecycleScope.launch {
                runCatching { app.catalogRepository.recordOpen(game) }
            }
            push(TabPushed.Game(game.appId, game.title))
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
                val homeState by homeVm.state.collectAsState()
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
                            profile = homeState.profile,
                            onGameClick = { game -> openGame(game, push) },
                            onProfileClick = { push(TabPushed.Profile) },
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
                    pushedHost = { pushed, onPop, replace ->
                        when (pushed) {
                            is TabPushed.Game -> GameScreen(
                                appId = pushed.appId,
                                title = pushed.title,
                                scripts = app.injectedScripts,
                                blockList = app.blockList,
                                onBack = onPop,
                            )
                            TabPushed.Auth -> AuthScreen(onClose = {
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
            if (uri.host?.endsWith("yandex.com") == true || uri.host?.endsWith("yandex.ru") == true) {
                val idx = pathSegments.indexOf("app")
                if (idx >= 0 && idx + 1 < pathSegments.size) pathSegments[idx + 1].toLongOrNull() else null
            } else null
        }
        else -> null
    }
}
