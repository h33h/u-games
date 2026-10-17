package dev.ugames

import java.io.File
import java.io.IOException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class OfflineGameStoreTest {
    @get:Rule val temporary = TemporaryFolder()
    private val entry = "https://app-42.cdn.games.yandex.net/game/index.html?lang=ru"
    private val script = "https://app-42.cdn.games.yandex.net/game/main.js?v=7"
    private val filter = AdResourceFilter(listOf("an.yandex.ru"), emptyList())

    private fun snapshot(resources: List<String> = listOf(script)) = OfflineCaptureReport(
        entryUrl = entry,
        title = "Космическая игра",
        resources = resources,
        storage = mapOf("level" to "5"),
        environment = "{\"i18n\":{\"lang\":\"ru\"}}",
        ready = true
    )

    private fun fixtureDownloader(failAt: String? = null) = OfflineDownloader { url, target, _ ->
        if (url == failAt) throw IOException("fixture download failed")
        val html = url == entry
        target.writeBytes(
            if (html) {
                "<!doctype html><script src='main.js?v=7'></script>".toByteArray()
            } else {
                byteArrayOf(
                    0,
                    1,
                    127,
                    -1
                )
            }
        )
        OfflineDownloadMetadata(
            if (html) "text/html" else "application/javascript",
            "utf-8",
            emptyMap()
        )
    }

    @Test fun publishedGameRestoresBytesMimeAndLocalProgressAcrossStoreInstances() {
        val root = temporary.newFolder()
        val saved = OfflineGameStore(root, filter, fixtureDownloader()).save(snapshot())
        val reopened = OfflineGameStore(root, filter, fixtureDownloader()).listGames().single()
        assertEquals(saved.id, reopened.id)
        assertEquals(entry, reopened.entryUrl)
        assertEquals("Космическая игра", reopened.title)
        assertEquals("5", reopened.storage["level"])
        assertEquals("application/javascript", reopened.resource(script)!!.mimeType)
        assertArrayEquals(byteArrayOf(0, 1, 127, -1), reopened.resource(script)!!.file.readBytes())
        assertNotNull(reopened.resource("$script#fragment"))
        assertNull(reopened.resource(script.replace("v=7", "v=8")))
        assertTrue(
            reopened.resource(
                script
            )!!.file.canonicalPath.startsWith(root.canonicalPath + File.separator)
        )
    }

    @Test fun savingSkipsAdvertisingSdkCatalogAuthenticationAndApiTraffic() {
        val requested = mutableListOf<String>()
        val downloader = OfflineDownloader { url, target, maximum ->
            requested += url
            fixtureDownloader().download(url, target, maximum)
        }
        OfflineGameStore(temporary.newFolder(), filter, downloader).save(
            snapshot(
                listOf(
                    script,
                    "https://an.yandex.ru/advert.js",
                    "https://yandex.ru/games/sdk.js",
                    "https://app-42.cdn.games.yandex.net/sdk/v2.js",
                    "https://yandex.ru/games/catalog.json",
                    "https://passport.yandex.ru/auth/profile.json",
                    "https://app-42.cdn.games.yandex.net/api/progress.json"
                )
            )
        )
        assertEquals(listOf(entry, script), requested)
    }

    @Test fun failedRefreshLeavesThePreviouslyPublishedGameAndNoPartialEntry() {
        val root = temporary.newFolder()
        OfflineGameStore(root, filter, fixtureDownloader()).save(snapshot())
        val failed = OfflineGameStore(root, filter, fixtureDownloader(failAt = script))
        assertThrows(IOException::class.java) { failed.save(snapshot()) }
        val saved = failed.listGames().single()
        assertArrayEquals(byteArrayOf(0, 1, 127, -1), saved.resource(script)!!.file.readBytes())
        assertFalse(root.listFiles()!!.any { it.name.startsWith(".partial-") })
    }

    @Test fun oversizedDownloadCannotPublishAReadyGame() {
        val store =
            OfflineGameStore(temporary.newFolder(), filter, fixtureDownloader(), maxGameBytes = 8)
        assertThrows(IOException::class.java) { store.save(snapshot()) }
        assertTrue(store.listGames().isEmpty())
    }

    @Test fun missingResourceOrNonHtmlEntryCannotAppearInTheLibrary() {
        val root = temporary.newFolder()
        val store = OfflineGameStore(root, filter, fixtureDownloader())
        val saved = store.save(snapshot())
        saved.resource(script)!!.file.delete()
        assertTrue(store.listGames().isEmpty())
        val invalid =
            OfflineGameStore(
                temporary.newFolder(),
                filter,
                OfflineDownloader { _, target, _ ->
                    target.writeText("{\"error\":\"authentication required\"}")
                    OfflineDownloadMetadata("application/json", "utf-8", emptyMap())
                }
            )
        assertThrows(IOException::class.java) { invalid.save(snapshot()) }
        assertTrue(invalid.listGames().isEmpty())
    }

    @Test fun deletingAGameRemovesItsPersistentFiles() {
        val root = temporary.newFolder()
        val store = OfflineGameStore(root, filter, fixtureDownloader())
        val saved = store.save(snapshot())
        store.delete(saved.id)
        assertTrue(store.listGames().isEmpty())
        assertTrue(root.listFiles()!!.isEmpty())
    }

    @Test fun entryFragmentIsKeptForLaunchWhileResourceKeysIgnoreFragments() {
        val saved = OfflineGameStore(
            temporary.newFolder(),
            filter,
            fixtureDownloader()
        ).save(snapshot().copy(entryUrl = "$entry#level-5"))
        assertEquals("$entry#level-5", saved.entryUrl)
        assertNotNull(saved.resource("$entry#level-5"))
    }

    @Test fun captureThatHasNotFinishedCannotPublishAGame() {
        val store = OfflineGameStore(temporary.newFolder(), filter, fixtureDownloader())
        assertThrows(IOException::class.java) { store.save(snapshot().copy(ready = false)) }
        assertTrue(store.listGames().isEmpty())
    }
}
