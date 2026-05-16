package games.yandex.wrap.network

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull

class EndpointRequestTest {
    @Test
    fun feedRequestContainsCatalogQueryAndJsonHeaders() {
        val request = FeedRequest(
            gamesPerPage = 12,
            pageId = "page-2",
        )

        assertEquals(HttpMethod.Get, request.method)
        assertEquals("yandex.ru", request.host)
        assertEquals("/games/api/catalogue/v2/feed/", request.path)
        assertEquals("https://yandex.ru/games/api/catalogue/v2/feed/", request.uri.toString())
        assertEquals("true", request.query["with_promos"])
        assertFalse(request.query.containsKey("lang"))
        assertEquals("12", request.query["games_count"])
        assertEquals("5", request.query["categorized_size"])
        assertEquals("true", request.query["with_recent_games"])
        assertEquals("android_other", request.query["platform"])
        assertNotNull(request.query["client_width"])
        assertNotNull(request.query["client_height"])
        assertEquals("page-2", request.query["page_id"])
        assertFalse(request.query.containsKey("tab"))
        assertFalse(request.query.containsKey("suggested_width"))
    }

    @Test
    fun searchRequestKeepsPaginationParams() {
        val request = SearchRequest(
            queryValue = "arcade",
            pageId = "next",
            gamesPerPage = 18,
        )

        assertEquals("https://yandex.ru/games/api/catalogue/v2/search/", request.uri.toString())
        assertEquals("arcade", request.query["query"])
        assertEquals("next", request.query["page_id"])
        assertEquals("18", request.query["games_count"])
        assertFalse(request.query.containsKey("lang"))
        assertEquals("android_other", request.query["platform"])
    }

    @Test
    fun detailRequestIsPostWithJsonBody() {
        val request = GameDetailRequest(appId = 42)

        assertEquals(HttpMethod.Post, request.method)
        assertEquals("https://yandex.ru/games/api/catalogue/v2/get_game", request.uri.toString())
        assertFalse(request.query.containsKey("lang"))
        assertEquals("application/json", request.contentType)
        assertNotNull(request.jsonBody)
        assertEquals("42", request.jsonBody["appID"]?.toString())
        assertEquals("\"app\"", request.jsonBody["format"]?.toString())
    }

    @Test
    fun userInfoRequestDoesNotOwnCookieHeader() {
        val request = UserInfoRequest()

        assertFalse(request.headers.containsKey("Cookie"))
        assertEquals("https://yandex.ru/games/api/catalogue/v2/user_info", request.uri.toString())
        assertFalse(request.query.containsKey("lang"))
    }
}
