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
import games.yandex.wrap.ui.components.FloatingTabBar
import games.yandex.wrap.ui.components.UGTab

/**
 * Per-tab pushed routes. Switching tabs preserves each tab's stack so a
 * user mid-Auth on Profile can flick to Home, browse, then come back to
 * Profile and resume the WebView push without losing scroll/state.
 */
sealed interface TabPushed {
    data object None : TabPushed
    data class Game(val appId: Long, val title: String) : TabPushed
    data object Auth : TabPushed
    data object Logs : TabPushed
    data object About : TabPushed
}

private data class TabState(
    val key: String,
    val tab: UGTab,
)

private val TABS = listOf(
    TabState("home", UGTab("home", "Home", Icons.Filled.Home)),
    TabState("browse", UGTab("browse", "Browse", Icons.Filled.GridView)),
    TabState("favorites", UGTab("favorites", "Favorites", Icons.Filled.Favorite)),
    TabState("profile", UGTab("profile", "Profile", Icons.Filled.AccountCircle)),
)

/**
 * Phase-2 tab container. Each tab owns its own `TabPushed` state; the bar
 * hides whenever the active tab has a non-None pushed route, so Game/Auth/
 * Logs/About cover the bar without leaking back to the user.
 *
 * `initialTab` and `initialPushed` let MainActivity drive deep-links — e.g.
 * `ugames://app/123` opens with the Home tab selected and a Game pushed
 * onto its stack.
 */
/**
 * Per-tab content slot. Receives:
 * - `push` — push a `TabPushed` route onto this tab's stack
 * - `switchTab` — switch the active tab from inside the content (e.g.
 *   Home's "See all" hops into Browse)
 */
typealias TabContent = @Composable (
    push: (TabPushed) -> Unit,
    switchTab: (String) -> Unit,
) -> Unit

@Composable
fun TabContainer(
    home: TabContent,
    browse: TabContent,
    favorites: TabContent,
    profile: TabContent,
    pushedHost: @Composable (TabPushed, onPop: () -> Unit) -> Unit,
    initialTab: String = "home",
    initialPushed: TabPushed = TabPushed.None,
) {
    var selected by remember { mutableStateOf(initialTab) }
    var homePushed by remember {
        mutableStateOf(if (initialTab == "home") initialPushed else TabPushed.None)
    }
    var browsePushed by remember {
        mutableStateOf(if (initialTab == "browse") initialPushed else TabPushed.None)
    }
    var favoritesPushed by remember {
        mutableStateOf(if (initialTab == "favorites") initialPushed else TabPushed.None)
    }
    var profilePushed by remember {
        mutableStateOf(if (initialTab == "profile") initialPushed else TabPushed.None)
    }

    val activePushed: TabPushed = when (selected) {
        "home" -> homePushed
        "browse" -> browsePushed
        "favorites" -> favoritesPushed
        else -> profilePushed
    }

    val switchTab: (String) -> Unit = { selected = it }

    Box(modifier = Modifier.fillMaxSize()) {
        when (selected) {
            "home" -> if (homePushed is TabPushed.None) home({ homePushed = it }, switchTab)
                       else pushedHost(homePushed) { homePushed = TabPushed.None }
            "browse" -> if (browsePushed is TabPushed.None) browse({ browsePushed = it }, switchTab)
                         else pushedHost(browsePushed) { browsePushed = TabPushed.None }
            "favorites" -> if (favoritesPushed is TabPushed.None) favorites({ favoritesPushed = it }, switchTab)
                            else pushedHost(favoritesPushed) { favoritesPushed = TabPushed.None }
            "profile" -> if (profilePushed is TabPushed.None) profile({ profilePushed = it }, switchTab)
                          else pushedHost(profilePushed) { profilePushed = TabPushed.None }
        }
        if (activePushed is TabPushed.None) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.BottomCenter,
            ) {
                FloatingTabBar(
                    tabs = TABS.map { it.tab },
                    selectedKey = selected,
                    onSelect = { key -> selected = key },
                )
            }
        }
    }
}
