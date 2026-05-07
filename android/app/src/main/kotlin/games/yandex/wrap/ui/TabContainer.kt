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
 *
 * Phase 3: each tab keeps a *stack* of these (`List<TabPushed>`), so
 * `Detail → Game → Back` lands back on Detail rather than the catalog.
 */
sealed interface TabPushed {
    data object None : TabPushed
    // Fully-qualified `catalog.Game` because inside the `TabPushed` body the
    // unqualified `Game` token resolves to the nested `TabPushed.Game` class
    // declared below, not to the imported `games.yandex.wrap.catalog.Game`.
    data class GameDetail(val game: games.yandex.wrap.catalog.Game) : TabPushed
    data class Game(val appId: Long, val title: String) : TabPushed
    data object Auth : TabPushed
    data object Logs : TabPushed
    data object About : TabPushed
    data object Profile : TabPushed
}

private data class TabState(
    val key: String,
    val tab: UGTab,
)

/// Phase-2.1: Profile lives behind the avatar in Home/Browse, not in the
/// tab-bar. Three tabs leave more room for breathing space and align with
/// the cleaned-up Home (no Favorites row).
private val TABS = listOf(
    TabState("home", UGTab("home", "Home", Icons.Filled.Home)),
    TabState("browse", UGTab("browse", "Browse", Icons.Filled.GridView)),
    TabState("favorites", UGTab("favorites", "Favorites", Icons.Filled.Favorite)),
)

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

/**
 * Host that renders a pushed route. Receives:
 * - `pushed` — the route at the top of the active tab's stack
 * - `push`   — append another route ON TOP of `pushed` (Phase 3:
 *              Detail.onPlay pushes Game on top so Back lands on Detail)
 * - `onPop`  — drop the top route from the active tab's stack
 * - `replace`— swap the top route in place (Profile → Auth/Logs/About)
 */
typealias PushedHost = @Composable (
    pushed: TabPushed,
    push: (TabPushed) -> Unit,
    onPop: () -> Unit,
    replace: (TabPushed) -> Unit,
) -> Unit

@Composable
fun TabContainer(
    home: TabContent,
    browse: TabContent,
    favorites: TabContent,
    pushedHost: PushedHost,
    initialTab: String = "home",
    initialPushed: TabPushed = TabPushed.None,
) {
    var selected by remember { mutableStateOf(initialTab) }
    var homeStack by remember {
        mutableStateOf<List<TabPushed>>(
            if (initialTab == "home" && initialPushed !is TabPushed.None) listOf(initialPushed) else emptyList()
        )
    }
    var browseStack by remember {
        mutableStateOf<List<TabPushed>>(
            if (initialTab == "browse" && initialPushed !is TabPushed.None) listOf(initialPushed) else emptyList()
        )
    }
    var favoritesStack by remember {
        mutableStateOf<List<TabPushed>>(
            if (initialTab == "favorites" && initialPushed !is TabPushed.None) listOf(initialPushed) else emptyList()
        )
    }

    val activeStack: List<TabPushed> = when (selected) {
        "home" -> homeStack
        "browse" -> browseStack
        else -> favoritesStack
    }
    val activePushed: TabPushed = activeStack.lastOrNull() ?: TabPushed.None

    val pushOnActive: (TabPushed) -> Unit = { route ->
        when (selected) {
            "home" -> homeStack = homeStack + route
            "browse" -> browseStack = browseStack + route
            "favorites" -> favoritesStack = favoritesStack + route
        }
    }
    val popOnActive: () -> Unit = {
        when (selected) {
            "home" -> homeStack = homeStack.dropLast(1)
            "browse" -> browseStack = browseStack.dropLast(1)
            "favorites" -> favoritesStack = favoritesStack.dropLast(1)
        }
    }
    val replaceOnActive: (TabPushed) -> Unit = { route ->
        when (selected) {
            "home" -> homeStack = homeStack.dropLast(1) + route
            "browse" -> browseStack = browseStack.dropLast(1) + route
            "favorites" -> favoritesStack = favoritesStack.dropLast(1) + route
        }
    }

    val switchTab: (String) -> Unit = { selected = it }

    Box(modifier = Modifier.fillMaxSize()) {
        if (activePushed is TabPushed.None) {
            when (selected) {
                "home" -> home(pushOnActive, switchTab)
                "browse" -> browse(pushOnActive, switchTab)
                "favorites" -> favorites(pushOnActive, switchTab)
            }
        } else {
            pushedHost(activePushed, pushOnActive, popOnActive, replaceOnActive)
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
