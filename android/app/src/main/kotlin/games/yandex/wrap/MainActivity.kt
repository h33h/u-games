package games.yandex.wrap

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.lifecycle.viewmodel.initializer
import games.yandex.wrap.ui.AuthScreen
import games.yandex.wrap.ui.CatalogScreen
import games.yandex.wrap.ui.CatalogViewModel
import games.yandex.wrap.ui.GameScreen
import games.yandex.wrap.ui.LogsScreen
import games.yandex.wrap.ui.theme.UGamesTheme

class MainActivity : ComponentActivity() {

    private val app: UGamesApplication
        get() = application as UGamesApplication

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val factory = viewModelFactory {
            initializer { CatalogViewModel(app.catalogRepository) }
        }
        val catalogVm = ViewModelProvider(this, factory)[CatalogViewModel::class.java]

        // ugames://app/<id> launches directly into the game frame.
        val initialRoute: Route = parseDeepLink(intent)?.let { appId ->
            Route.Game(appId, "")
        } ?: Route.Catalog

        setContent {
            UGamesTheme {
                var route by remember { mutableStateOf<Route>(initialRoute) }
                when (val r = route) {
                        Route.Catalog -> CatalogScreen(
                            viewModel = catalogVm,
                            onGameClick = { game ->
                                catalogVm.recordGameOpen(game)
                                route = Route.Game(game.appId, game.title)
                            },
                            onLoginClick = { route = Route.Auth },
                            onLogsRequest = { route = Route.Logs },
                        )
                        is Route.Game -> GameScreen(
                            appId = r.appId,
                            title = r.title,
                            scripts = app.injectedScripts,
                            blockList = app.blockList,
                            onBack = { route = Route.Catalog },
                        )
                        Route.Auth -> AuthScreen(onClose = {
                            catalogVm.refreshProfile()
                            route = Route.Catalog
                        })
                    Route.Logs -> LogsScreen(onClose = { route = Route.Catalog })
                }
            }
        }
    }
}

private sealed interface Route {
    data object Catalog : Route
    data object Auth : Route
    data object Logs : Route
    data class Game(val appId: Long, val title: String) : Route
}

/// Parse ugames://app/<id> deep links. Returns the appId if the URI matches,
/// null otherwise (so callers fall back to Catalog). Tolerant: also accepts
/// https://yandex.com/games/app/<id> intents in case Android's auto-verify
/// claims the URL even though we don't ship Digital Asset Links.
private fun parseDeepLink(intent: android.content.Intent?): Long? {
    val uri = intent?.data ?: return null
    val scheme = uri.scheme?.lowercase() ?: return null
    val pathSegments = uri.pathSegments
    return when (scheme) {
        "ugames" -> {
            // ugames://app/<id> — host="app", first path segment is the id
            if (uri.host == "app") pathSegments.firstOrNull()?.toLongOrNull() else null
        }
        "https", "http" -> {
            // https://yandex.com/games/app/<id>
            if (uri.host?.endsWith("yandex.com") == true || uri.host?.endsWith("yandex.ru") == true) {
                val idx = pathSegments.indexOf("app")
                if (idx >= 0 && idx + 1 < pathSegments.size) pathSegments[idx + 1].toLongOrNull() else null
            } else null
        }
        else -> null
    }
}
