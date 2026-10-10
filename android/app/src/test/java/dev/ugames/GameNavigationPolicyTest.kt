package dev.ugames

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GameNavigationPolicyTest {
    @Test fun postDocumentsAreBlockedWithoutBlockingGameApiRequests() {
        val url = "https://external.example/submit"
        val headers = mapOf(
            "Referer" to "https://app-388224.cdn.games.yandex.net/game/index.html",
            "Accept" to "text/html"
        )
        assertTrue(GameNavigationPolicy.blocksDocumentRequest(url, false, headers))
        assertTrue(
            GameNavigationPolicy.blocksDocumentRequest(
                url,
                false,
                headers + ("Sec-Fetch-Dest" to "iframe")
            )
        )
        assertFalse(
            GameNavigationPolicy.blocksDocumentRequest(
                url,
                false,
                headers + ("Sec-Fetch-Dest" to "empty")
            )
        )
        assertTrue(GameNavigationPolicy.blocksDocumentRequest(url, true, emptyMap()))
        assertTrue(
            GameNavigationPolicy.blocksDocumentRequest(
                url,
                false,
                headers + ("Accept" to "text/html,application/xhtml+xml")
            )
        )
        assertTrue(
            GameNavigationPolicy.blocksDocumentRequest(
                url,
                false,
                headers + ("Upgrade-Insecure-Requests" to "1")
            )
        )
        assertFalse(
            GameNavigationPolicy.blocksDocumentRequest(
                "data:text/html,game",
                true,
                emptyMap()
            )
        )
    }

    @Test fun supportsS3GameHosting() {
        assertTrue(
            GameNavigationPolicy.allowsFrame(
                "https://app-374241.games.s3.yandex.net/helpers/fake-page",
                "https://yandex.ru/games/"
            )
        )
    }

    @Test fun framesCannotLeaveTheGameOriginEvenForScriptedNavigation() {
        val source = "https://app-388224.cdn.games.yandex.net/game/index.html"
        assertTrue(
            GameNavigationPolicy.allowsFrame(
                "https://app-388224.cdn.games.yandex.net/game/level2",
                source
            )
        )
        assertTrue(GameNavigationPolicy.allowsFrame(source, "https://yandex.ru/games/app/388224"))
        assertTrue(
            GameNavigationPolicy.allowsFrame(
                "https://game.example/level2",
                "https://game.example/play"
            )
        )
        for (url in listOf(
            "https://external.example",
            "https://game.example:444/",
            "https://games.yandex.net.evil.test/",
            "intent://open"
        )) {
            assertFalse(url, GameNavigationPolicy.allowsFrame(url, source))
        }
    }

    @Test fun onlyGamePortalCanReplaceTheMainWindow() {
        for (url in listOf(
            "https://yandex.ru/games/",
            "https://yandex.com/games/app/123",
            "https://passport.yandex.ru/auth",
            "about:blank"
        )) {
            assertTrue(url, GameNavigationPolicy.allows(url))
        }
        for (url in listOf(
            "https://example.com",
            "https://yandex.ru.evil.test/games/",
            "https://yandex.ru/games-evil",
            "https://yandex.ru/support/games/",
            "https://passport.yandex.ru/profile",
            "intent://game",
            "data:text/html,hello",
            "https://yandex.ru:444/games/"
        )) {
            assertFalse(url, GameNavigationPolicy.allows(url))
        }
    }
}
