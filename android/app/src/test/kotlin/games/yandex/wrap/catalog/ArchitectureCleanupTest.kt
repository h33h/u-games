package games.yandex.wrap.catalog

import games.yandex.wrap.config.AppConfig
import games.yandex.wrap.util.dedupeBy
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ArchitectureCleanupTest {
    @Test
    fun yandexEndpointsCentralizeHostsUserAgentAndRoutes() {
        val config = AppConfig.defaultForLocale(language = "ru")

        assertEquals("https://yandex.ru/games/", config.yandex.gamesHome().toString())
        assertEquals("https://passport.yandex.ru", config.yandex.passportOrigin().toString())
        assertEquals("https://yandex.ru/games/api/catalogue/v2/feed/", config.yandex.feedApi().toString())
        assertEquals("https://yandex.ru/games/api/catalogue/v2/search/", config.yandex.searchApi().toString())
        assertEquals("https://yandex.ru/games/api/catalogue/v2/similar_games/", config.yandex.similarApi().toString())
        assertEquals("https://yandex.ru/games/api/catalogue/v2/get_game", config.yandex.gameDetailApi().toString())
        assertEquals("https://yandex.ru/games/api/catalogue/v2/tags/", config.yandex.tagsApi().toString())
        assertEquals("https://yandex.ru/games/api/catalogue/v2/user_info", config.yandex.userInfoApi().toString())
        assertEquals("https://yandex.ru/games/app/42", config.yandex.gameUrl(42).toString())
        assertEquals(listOf("https://yandex.ru", "https://passport.yandex.ru"), config.yandex.cookieOrigins())
        assertTrue(config.http.userAgent.contains("Mobile"))
    }

    @Test
    fun dedupeByPreservesFirstOccurrenceForAnyType() {
        data class Item(val id: Int, val value: String)

        val result = listOf(
            Item(1, "first"),
            Item(2, "second"),
            Item(1, "duplicate"),
        ).dedupeBy { it.id }

        assertEquals(listOf(Item(1, "first"), Item(2, "second")), result)
    }

    @Test
    fun networkPolicyClassifiesTransientErrorsWithoutCatalogTypes() {
        assertTrue(NetworkErrorPolicy.isTransient(HttpStatusException(503)))
        assertTrue(NetworkErrorPolicy.isTransient(HttpStatusException(599)))
        assertFalse(NetworkErrorPolicy.isTransient(HttpStatusException(404)))
    }

    @Test
    fun appDetailParserReturnsNullWhenGetGameDoesNotContainGameObject() {
        val detail = YandexCatalogJsonParser().appDetail(kotlinx.serialization.json.JsonObject(emptyMap()))

        assertNull(detail)
    }
}
