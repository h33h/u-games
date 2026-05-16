package games.yandex.wrap.catalog

import games.yandex.wrap.config.AppConfig
import games.yandex.wrap.config.YandexHost
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

        assertEquals(YandexHost.Ru, config.yandex.preferredHost)
        assertEquals("https://yandex.ru/games/", config.yandex.gamesHome().toString())
        assertEquals("https://passport.yandex.ru", config.yandex.passportOrigin().toString())
        assertEquals("https://yandex.com/games/api/catalogue/v2/feed/", config.yandex.feedApi().toString())
        assertEquals("https://yandex.com/games/app/42", config.yandex.gameUrl(42).toString())
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
    fun appDetailParserReturnsNullWhenJsonLdDoesNotContainGameNode() {
        val detail = CatalogHtmlParser().appDetailFromJsonLd("""{"@graph":[{"@type":"BreadcrumbList"}]}""")

        assertNull(detail)
    }
}
