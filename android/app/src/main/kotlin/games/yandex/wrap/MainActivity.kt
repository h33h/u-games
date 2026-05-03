package games.yandex.wrap

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.lifecycle.viewmodel.initializer
import games.yandex.wrap.ui.AuthScreen
import games.yandex.wrap.ui.CatalogScreen
import games.yandex.wrap.ui.CatalogViewModel
import games.yandex.wrap.ui.GameScreen

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

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                Surface(color = Color.Black) {
                    var route by remember { mutableStateOf<Route>(Route.Catalog) }
                    when (val r = route) {
                        Route.Catalog -> CatalogScreen(
                            viewModel = catalogVm,
                            onGameClick = { route = Route.Game(it.appId, it.title) },
                            onLoginClick = { route = Route.Auth },
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
                    }
                }
            }
        }
    }
}

private sealed interface Route {
    data object Catalog : Route
    data object Auth : Route
    data class Game(val appId: Long, val title: String) : Route
}
