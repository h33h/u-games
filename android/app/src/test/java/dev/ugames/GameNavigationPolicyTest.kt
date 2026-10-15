package dev.ugames

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GameNavigationPolicyTest {
    @Test fun yandexIdCanFinishSSOAndSynchronizeCookies() {
        for (url in listOf(
            "https://sso.passport.yandex.ru/prepare?uuid=fixture&goal=https%3A%2F%2Fya.ru%2F&finish=https%3A%2F%2Fyandex.ru%2Fgames%2F",
            "https://sso.passport.yandex.com/prepare?uuid=fixture",
            "https://sso.ya.ru/sync?uuid=fixture"
        )) {
            assertTrue(url, GameNavigationPolicy.allows(url))
            assertTrue(
                url,
                GameNavigationPolicy.allowsFrame(
                    url,
                    "https://passport.yandex.ru/pwl-yandex/auth/finished"
                )
            )
            assertFalse(GameNavigationPolicy.blocksDocumentRequest(url, true, emptyMap()))
            assertFalse(
                GameNavigationPolicy.blocksDocumentRequest(
                    url,
                    false,
                    mapOf("Sec-Fetch-Dest" to "iframe")
                )
            )
        }
        for (url in listOf(
            "https://sso.passport.yandex.ru/profile",
            "https://sso.passport.yandex.ru/prepare-evil",
            "https://sso.passport.yandex.ru.evil.test/prepare",
            "https://sso.ya.ru/profile",
            "https://sso.ya.ru/sync-evil",
            "https://sso.ya.ru.evil.test/sync",
            "http://sso.ya.ru/sync",
            "https://sso.ya.ru:444/sync"
        )) {
            assertFalse(url, GameNavigationPolicy.allows(url))
            assertFalse(
                url,
                GameNavigationPolicy.allowsFrame(url, "https://sso.passport.yandex.ru/prepare")
            )
        }
    }

    @Test fun currentYandexIdLoginAndVerificationCanOpen() {
        for (url in listOf(
            "https://passport.yandex.ru/pwl-yandex/auth/add?retpath=https%3A%2F%2Fyandex.ru%2Fgames%2F",
            "https://passport.yandex.com/pwl-yandex/auth/verify"
        )) {
            assertTrue(url, GameNavigationPolicy.allows(url))
            assertFalse(GameNavigationPolicy.blocksDocumentRequest(url, true, emptyMap()))
        }
        assertFalse(GameNavigationPolicy.allows("https://passport.yandex.ru/pwl-yandex-evil/auth"))
        assertFalse(
            GameNavigationPolicy.allows("https://passport.yandex.ru.evil.test/pwl-yandex/auth")
        )
    }

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
