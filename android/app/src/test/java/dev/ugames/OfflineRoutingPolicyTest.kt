package dev.ugames

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class OfflineRoutingPolicyTest {
    private val entry = "https://app-42.cdn.games.yandex.net/index.html?lang=ru"
    private val game =
        SavedOfflineGame("a".repeat(64), entry, "Fixture", 1, 0, emptyMap(), "{}", emptyMap())

    @Test fun validatedInternetAlwaysUsesTheNormalNetworkEvenWhenTheGameWasCached() {
        assertNull(OfflineRoutingPolicy.cachedGame(entry, true, listOf(game)))
    }

    @Test fun offlineStartupShowsTheOrdinaryCatalogueEvenAfterPlayingACachedGame() {
        assertEquals("https://yandex.ru/games/", OfflineRoutingPolicy.startupUrl(false, entry))
        assertEquals(entry, OfflineRoutingPolicy.startupUrl(true, entry))
    }

    @Test fun onlyAnAvailableCachedEntryCanBeOpenedOffline() {
        assertSame(game, OfflineRoutingPolicy.cachedGame("$entry#level-5", false, listOf(game)))
        assertNull(
            OfflineRoutingPolicy.cachedGame(entry.replace("app-42", "app-43"), false, listOf(game))
        )
    }
}
