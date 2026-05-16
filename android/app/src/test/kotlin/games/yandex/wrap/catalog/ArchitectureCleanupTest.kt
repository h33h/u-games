package games.yandex.wrap.catalog

import games.yandex.wrap.utils.Constants
import games.yandex.wrap.network.isTransientNetworkError
import games.yandex.wrap.util.dedupeBy
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ArchitectureCleanupTest {
    @Test
    fun yandexConstantsCentralizeSharedHostsAndRoutes() {
        assertEquals("yandex.ru", Constants.Network.host)
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
    fun throwableExtensionClassifiesTransientNetworkErrors() {
        assertTrue(IOException("network").isTransientNetworkError)
        assertFalse(IllegalStateException("decode").isTransientNetworkError)
    }

    @Test
    fun appDetailParserReturnsNullWhenGetGameDoesNotContainGameObject() {
        val detail = YandexCatalogJsonParser().appDetail(kotlinx.serialization.json.JsonObject(emptyMap()))

        assertNull(detail)
    }
}
