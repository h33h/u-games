package dev.ugames

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OfflineResourcePolicyTest {
    private val entry = "https://app-42.cdn.games.yandex.net/game/index.html?lang=ru"

    @Test fun normalizationPreservesQueryAndRejectsInsecureOrCredentialedUrls() {
        assertEquals(
            "https://app-42.cdn.games.yandex.net/game/a.js?v=1",
            OfflineResourcePolicy.normalize(
                "https://APP-42.cdn.games.yandex.net:443/game/a.js?v=1#x"
            )
        )
        for (url in listOf(
            "http://app-42.cdn.games.yandex.net/a.js",
            "file:///tmp/a.js",
            "https://user:password@app-42.cdn.games.yandex.net/a.js",
            "https://app-42.cdn.games.yandex.net:444/a.js"
        )) {
            assertNull(url, OfflineResourcePolicy.normalize(url))
        }
    }

    @Test fun capturedGameMustMatchTheTrustedMessageOrigin() {
        val message = JSONObject().put("version", 1).put("url", entry).put("title", "game")
            .put("ready", true).put("resources", org.json.JSONArray().put(entry))
            .put("storage", JSONObject().put("level", "4")).toString()
        val report = OfflineCaptureReport.parse(
            message,
            "https://app-42.cdn.games.yandex.net",
            "Космос"
        )
        assertNotNull(report)
        assertEquals("Космос", report!!.title)
        assertEquals("4", report.storage["level"])
        assertNull(OfflineCaptureReport.parse(message, "https://app-43.cdn.games.yandex.net", ""))
        assertNull(
            OfflineCaptureReport.parse(message, "https://app-42.cdn.games.yandex.net.evil.test", "")
        )
        assertNull(OfflineCaptureReport.parse(message, "https://yandex.ru", ""))
    }

    @Test fun resourcePolicyAllowsGameDataAndPublicStaticAssetsButNotServiceResponses() {
        assertTrue(
            OfflineResourcePolicy.canSave(
                entry,
                "https://app-42.cdn.games.yandex.net/game/levels.json"
            )
        )
        assertTrue(OfflineResourcePolicy.canSave(entry, "https://yastatic.net/games/runtime.js"))
        assertFalse(OfflineResourcePolicy.canSave(entry, "https://api.example.com/player.json"))
        assertFalse(
            OfflineResourcePolicy.canSave(
                entry,
                "https://app-42.cdn.games.yandex.net/api/player.json"
            )
        )
        assertFalse(OfflineResourcePolicy.canSave(entry, "https://yandex.ru/games/catalog.json"))
        assertFalse(OfflineResourcePolicy.canSave(entry, "https://passport.yandex.ru/auth.js"))
        assertFalse(
            OfflineResourcePolicy.canSave(
                entry,
                "https://cdn.example.com/resource-without-extension"
            )
        )
        assertFalse(
            OfflineResourcePolicy.isGameUrl("https://games.yandex.net.evil.test/index.html")
        )
        assertTrue(OfflineResourcePolicy.isGameUrl("https://app-42.games.s3.yandex.net/index.html"))
    }

    @Test fun malformedOrOversizedCaptureDoesNotBecomeSaveable() {
        assertNull(
            OfflineCaptureReport.parse("not JSON", "https://app-42.cdn.games.yandex.net", "")
        )
        assertNull(
            OfflineCaptureReport.parse(
                " ".repeat(2 * 1024 * 1024 + 1),
                "https://app-42.cdn.games.yandex.net",
                ""
            )
        )
    }

    @Test fun defaultEngineTitleUsesTheCatalogGameName() {
        val message = JSONObject().put("version", 1).put("url", entry)
            .put("title", "New project").put("ready", true)
            .put("resources", org.json.JSONArray().put(entry)).toString()
        assertEquals(
            "Космос",
            OfflineCaptureReport.parse(
                message,
                "https://app-42.cdn.games.yandex.net",
                "Космос"
            )!!.title
        )
    }
}
