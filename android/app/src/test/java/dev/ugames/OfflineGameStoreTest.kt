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
        val html = java.net.URI(url).path.endsWith("index.html")
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
            OfflineGameStore(temporary.newFolder(), filter, fixtureDownloader(), maxCacheBytes = 8)
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

    @Test fun aggregateBudgetEvictsTheLeastRecentlyPlayedGame() {
        val root = temporary.newFolder()
        val transport = OfflineDownloader { url, target, _ ->
            target.writeBytes(
                if (url.endsWith(".html")) "<!doctype html>".toByteArray() else ByteArray(1500)
            )
            OfflineDownloadMetadata(
                if (url.endsWith(".html")) "text/html" else "application/javascript",
                "utf-8",
                emptyMap()
            )
        }
        val store = OfflineGameStore(root, filter, transport, maxCacheBytes = 6000, clock = { 100 })
        fun game(number: Int) = snapshot().copy(
            entryUrl = "https://app-$number.cdn.games.yandex.net/index.html",
            resources = listOf("https://app-$number.cdn.games.yandex.net/game.js")
        )
        store.save(game(41), playedAt = 1)
        store.save(game(42), playedAt = 2)
        store.touch(game(41).entryUrl, 3)
        store.save(game(43), playedAt = 4)
        assertEquals(
            listOf(43, 41),
            store.listGames().map {
                Regex("app-(\\d+)").find(it.entryUrl)!!.groupValues[1].toInt()
            }
        )
        assertTrue(root.walkTopDown().filter { it.isFile }.sumOf { it.length() } <= 6000)
    }

    @Test fun packageMetadataAndStagingCountTowardTheAggregateBudget() {
        val root = temporary.newFolder()
        val store = OfflineGameStore(root, filter, fixtureDownloader(), maxCacheBytes = 100)
        assertThrows(IOException::class.java) { store.save(snapshot()) }
        assertTrue(store.listGames().isEmpty())
        assertTrue(root.walkTopDown().filter { it.isFile }.sumOf { it.length() } <= 100)
    }

    @Test fun replayTouchProtectsTheOlderGameAndSaveCompletionCannotOverridePlayOrder() {
        val root = temporary.newFolder()
        var now = 100L
        val store = OfflineGameStore(root, filter, fixtureDownloader(), clock = { now })
        val first = store.save(snapshot(), playedAt = 10)
        val other = snapshot().copy(
            entryUrl = entry.replace("app-42", "app-43"),
            resources = emptyList()
        )
        store.save(other, playedAt = 20)
        store.touch(first.entryUrl, 30)
        now = 500
        store.save(other, playedAt = 20)
        assertEquals(first.id, store.listGames().first().id)
        val reopened = OfflineGameStore(root, filter, fixtureDownloader())
        assertEquals(30, reopened.listGames().first().lastPlayedAt)
    }

    @Test fun reportsReuseBytesOnlyDuringTheSameOnlineVisitAndKeepProgressFresh() {
        val root = temporary.newFolder()
        val requested = mutableListOf<String>()
        var revision = 1
        val transport = OfflineDownloader { url, target, _ ->
            requested += url
            target.writeText(if (url == entry) "<!doctype html>$revision" else "revision=$revision")
            OfflineDownloadMetadata(
                if (url ==
                    entry
                ) {
                    "text/html"
                } else {
                    "application/javascript"
                },
                "utf-8",
                emptyMap()
            )
        }
        val store = OfflineGameStore(root, filter, transport)
        store.save(snapshot(), visitId = "one", playedAt = 1)
        val extended = store.save(
            snapshot(
                listOf(script, script.replace("main.js", "extra.js"))
            ).copy(storage = mapOf("level" to "9")),
            visitId = "one",
            playedAt = 2
        )
        assertEquals(listOf(entry, script, script.replace("main.js", "extra.js")), requested)
        assertEquals("9", extended.storage["level"])
        revision = 2
        val refreshed = store.save(snapshot(), visitId = "two", playedAt = 3)
        assertEquals(2, requested.count { it == entry })
        assertEquals("revision=2", refreshed.resource(script)!!.file.readText())
    }

    @Test fun anActiveOfflineGameIsNotEvictedForANewDownload() {
        val root = temporary.newFolder()
        val transport = OfflineDownloader { url, target, _ ->
            target.writeBytes(
                if (url.endsWith(".html")) "<!doctype html>".toByteArray() else ByteArray(1500)
            )
            OfflineDownloadMetadata(
                if (url.endsWith(".html")) "text/html" else "application/javascript",
                "utf-8",
                emptyMap()
            )
        }
        val store = OfflineGameStore(root, filter, transport, maxCacheBytes = 4000)
        val first = store.save(
            snapshot().copy(entryUrl = entry.substringBefore('?'), resources = listOf(script))
        )
        store.pin(first.id)
        assertThrows(IOException::class.java) {
            store.save(
                snapshot().copy(
                    entryUrl = entry.replace("app-42", "app-43").substringBefore('?'),
                    resources = listOf(script.replace("app-42", "app-43"))
                )
            )
        }
        assertEquals(first.id, store.listGames().single().id)
        assertTrue(first.resource(script)!!.file.exists())
        store.unpin(first.id)
    }

    @Test fun readingTheIndexDoesNotWaitForANetworkDownload() {
        val entered = java.util.concurrent.CountDownLatch(1)
        val release = java.util.concurrent.CountDownLatch(1)
        val read = java.util.concurrent.CountDownLatch(1)
        val store =
            OfflineGameStore(
                temporary.newFolder(),
                filter,
                OfflineDownloader {
                        url,
                        target,
                        maximum
                    ->
                    entered.countDown()
                    release.await(3, java.util.concurrent.TimeUnit.SECONDS)
                    fixtureDownloader().download(url, target, maximum)
                }
            )
        val save = Thread { store.save(snapshot()) }
        val listing = Thread {
            store.listGames()
            read.countDown()
        }
        save.start()
        try {
            assertTrue(entered.await(1, java.util.concurrent.TimeUnit.SECONDS))
            listing.start()
            assertTrue(
                "The index must remain available while transport is blocked",
                read.await(250, java.util.concurrent.TimeUnit.MILLISECONDS)
            )
        } finally {
            release.countDown()
            save.join(4000)
            listing.join(4000)
        }
    }

    @Test fun catalogueMetadataEnrichesEngineTitleAndPersistsOnlyALocalRasterCover() {
        val root = temporary.newFolder()
        val cover = "https://avatars.mds.yandex.net/get-games/123/cover/medium"
        val png = java.util.Base64.getDecoder().decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lE" +
                "QVR42mP8/x8AAusB9Y9Z4xkAAAAASUVORK5CYII="
        )
        val transport = OfflineDownloader { url, target, maximum ->
            if (url == cover) {
                target.writeBytes(png)
                OfflineDownloadMetadata("image/png", null, emptyMap())
            } else {
                fixtureDownloader().download(url, target, maximum)
            }
        }
        val store = OfflineGameStore(root, filter, transport)
        store.rememberCatalog(
            OfflineCatalogMetadata("42", "https://yandex.ru/games/app/42", "Космос", cover)
        )
        val saved = store.save(snapshot().copy(title = "New project"))
        assertEquals("Космос", saved.title)
        assertArrayEquals(png, saved.cover!!.file.readBytes())
        assertTrue(saved.coverLocalUrl!!.startsWith("https://yandex.ru/games/.ugames-cache-cover/"))
        assertEquals("Космос", OfflineGameStore(root, filter, transport).listGames().single().title)
    }

    @Test fun failedOptionalCoverDoesNotDiscardAnOtherwisePlayableGame() {
        val store = OfflineGameStore(temporary.newFolder(), filter, fixtureDownloader())
        store.rememberCatalog(
            OfflineCatalogMetadata(
                "42",
                "https://yandex.ru/games/app/42",
                "Космос",
                "https://avatars.mds.yandex.net/get-games/123/cover/medium"
            )
        )
        val saved = store.save(snapshot())
        assertEquals("Космос", saved.title)
        assertNull(saved.cover)
        assertNotNull(saved.resource(entry))
    }

    @Test fun aFreshLargeVisitCanEvictItsPreviousSnapshotWhenBothCannotFit() {
        val root = temporary.newFolder()
        var revision = 1
        val store = OfflineGameStore(
            root,
            filter,
            OfflineDownloader { url, target, _ ->
                target.writeBytes(
                    if (url ==
                        entry
                    ) {
                        "<!doctype html>$revision".toByteArray()
                    } else {
                        ByteArray(1500) { revision.toByte() }
                    }
                )
                OfflineDownloadMetadata(
                    if (url ==
                        entry
                    ) {
                        "text/html"
                    } else {
                        "application/javascript"
                    },
                    "utf-8",
                    emptyMap()
                )
            },
            maxCacheBytes = 4000
        )
        val first = store.save(snapshot(), visitId = "one")
        revision = 2
        val refreshed = store.save(snapshot(), visitId = "two")
        assertEquals(first.id, refreshed.id)
        assertEquals(2, refreshed.resource(script)!!.file.readBytes()[0].toInt())
        assertEquals(1, store.listGames().size)
        assertTrue(root.walkTopDown().filter { it.isFile }.sumOf { it.length() } <= 4000)
    }

    @Test fun recoveryRemovesUnpublishedResourceFilesBeforeEvictingAValidGame() {
        val root = temporary.newFolder()
        val saved = OfflineGameStore(root, filter, fixtureDownloader()).save(snapshot())
        val actual = root.walkTopDown().filter { it.isFile }.sumOf { it.length() }
        File(
            saved.resource(entry)!!.file.parentFile,
            "orphan-from-interrupted-manifest"
        ).writeBytes(ByteArray(500))
        val recovered = OfflineGameStore(
            root,
            filter,
            fixtureDownloader(),
            maxCacheBytes =
                actual + 1
        )
        assertEquals(saved.id, recovered.listGames().single().id)
        assertTrue(root.walkTopDown().filter { it.isFile }.sumOf { it.length() } <= actual + 1)
    }

    @Test fun replayLeaseResolvesTheCurrentSnapshotAndKeepsItUntilClosed() {
        val root = temporary.newFolder()
        val store = OfflineGameStore(root, filter, fixtureDownloader())
        val heldIndex = store.save(snapshot(), visitId = "old")
        val refreshed = store.save(snapshot(), visitId = "new")
        val lease = requireNotNull(store.acquire(heldIndex.id, playedAt = 100))
        assertEquals(refreshed.resource(entry)!!.file, lease.game.resource(entry)!!.file)
        assertFalse(heldIndex.resource(entry)!!.file.exists())
        store.delete(lease.game.id)
        assertTrue(lease.game.resource(entry)!!.file.exists())
        assertThrows(IOException::class.java) { store.save(snapshot(), visitId = "another") }
        lease.close()
        lease.close()
        store.delete(refreshed.id)
        assertTrue(store.listGames().isEmpty())
    }
}
