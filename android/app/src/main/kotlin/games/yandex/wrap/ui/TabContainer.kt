package games.yandex.wrap.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Home
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import games.yandex.wrap.ui.components.EmptyState
import games.yandex.wrap.ui.components.FloatingTabBar
import games.yandex.wrap.ui.components.UGTab

/**
 * Phase 1 tab container. Home renders the existing CatalogScreen (passed in
 * via the [home] slot), other tabs are EmptyState placeholders. The bar is
 * hidden when [hideBar] is true (e.g., when caller pushes Game/Auth/Logs
 * over the container).
 */
@Composable
fun TabContainer(
    hideBar: Boolean,
    home: @Composable () -> Unit,
) {
    var selected by remember { mutableStateOf("home") }
    Box(modifier = Modifier.fillMaxSize()) {
        when (selected) {
            "home" -> home()
            "browse" -> EmptyState(
                icon = Icons.Filled.GridView,
                title = "Browse — coming soon",
                body = "Genre filters and sort will land here.",
            )
            "favorites" -> EmptyState(
                icon = Icons.Filled.Favorite,
                title = "Favorites — coming soon",
                body = "Saved games will live here.",
            )
            "profile" -> EmptyState(
                icon = Icons.Filled.AccountCircle,
                title = "Profile — coming soon",
                body = "Sign in / Plus / Logs.",
            )
        }
        if (!hideBar) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.BottomCenter,
            ) {
                FloatingTabBar(
                    tabs = listOf(
                        UGTab("home", "Home", Icons.Filled.Home),
                        UGTab("browse", "Browse", Icons.Filled.GridView),
                        UGTab("favorites", "Favorites", Icons.Filled.Favorite),
                        UGTab("profile", "Profile", Icons.Filled.AccountCircle),
                    ),
                    selectedKey = selected,
                    onSelect = { selected = it },
                )
            }
        }
    }
}
