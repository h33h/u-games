package dev.ugames

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class AutomaticOfflineCacheTest {
    @get:Rule val temporary = TemporaryFolder()
    private val entry = "https://app-42.cdn.games.yandex.net/index.html"
    private fun report(vararg paths: String) = OfflineCaptureReport(
        entry,
        "Fixture",
        paths.map {
            "https://app-42.cdn.games.yandex.net/$it"
        },
        emptyMap(),
        "{}",
        true
    )

    @Test fun recurringReportsPreserveNewResourcesAndProgressWithoutRepeatedDownloads() {
        val requests = mutableListOf<String>()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        val store =
            OfflineGameStore(
                temporary.newFolder(),
                AdResourceFilter(emptyList(), emptyList()),
                OfflineDownloader {
                        url,
                        target,
                        _
                    ->
                    requests += url
                    if (url == entry) {
                        entered.countDown()
                        release.await(3, TimeUnit.SECONDS)
                    }
                    target.writeText(if (url == entry) "<!doctype html>" else "resource")
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
            )
        val cache = AutomaticOfflineCache(store, executor)
        try {
            cache.setEnabled(true)
            cache.offer(report("first.js"), "visit", 10)
            assertTrue(entered.await(1, TimeUnit.SECONDS))
            cache.offer(
                report("first.js", "second.js").copy(storage = mapOf("level" to "7")),
                "visit",
                11
            )
            cache.offer(
                report("first.js", "second.js").copy(storage = mapOf("level" to "8")),
                "visit",
                12
            )
            release.countDown()
            executor.submit {}.get(5, TimeUnit.SECONDS)
            cache.offer(
                report("first.js", "second.js").copy(storage = mapOf("level" to "8")),
                "visit",
                13
            )
            executor.submit {}.get(5, TimeUnit.SECONDS)
            assertEquals(
                listOf(
                    entry,
                    entry.substringBeforeLast('/') + "/first.js",
                    entry.substringBeforeLast('/') + "/second.js"
                ),
                requests
            )
            assertEquals("8", store.listGames().single().storage["level"])
            assertEquals(13, store.listGames().single().lastPlayedAt)
        } finally {
            release.countDown()
            cache.setEnabled(false)
            executor.shutdownNow()
        }
    }

    @Test fun leavingTheForegroundCancelsPendingWorkAndCannotPublishTheActiveDownload() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        val root = temporary.newFolder()
        val store =
            OfflineGameStore(
                root,
                AdResourceFilter(emptyList(), emptyList()),
                OfflineDownloader {
                        _,
                        target,
                        _
                    ->
                    entered.countDown()
                    release.await(3, TimeUnit.SECONDS)
                    target.writeText("<!doctype html>")
                    OfflineDownloadMetadata("text/html", "utf-8", emptyMap())
                }
            )
        val cache = AutomaticOfflineCache(store, executor)
        try {
            cache.setEnabled(true)
            cache.offer(report(), "visit", 1)
            assertTrue(entered.await(1, TimeUnit.SECONDS))
            cache.setEnabled(false)
            release.countDown()
            cache.offer(report(), "visit", 2)
            executor.submit {}.get(5, TimeUnit.SECONDS)
            assertTrue(store.listGames().isEmpty())
            assertFalse(root.listFiles().orEmpty().any { it.name.startsWith(".partial-") })
        } finally {
            release.countDown()
            executor.shutdownNow()
        }
    }

    @Test fun recurringProgressReportsBackOffAfterAFailedWholeSnapshot() {
        val requests = mutableListOf<String>()
        val executor = Executors.newSingleThreadExecutor()
        var now = 0L
        var fail = true
        val store =
            OfflineGameStore(
                temporary.newFolder(),
                AdResourceFilter(emptyList(), emptyList()),
                OfflineDownloader {
                        url,
                        target,
                        _
                    ->
                    requests += url
                    if (url != entry && fail) throw java.io.IOException("fixture unavailable")
                    target.writeText(if (url == entry) "<!doctype html>" else "resource")
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
            )
        val cache = AutomaticOfflineCache(store, executor, clock = { now })
        try {
            cache.setEnabled(true)
            cache.offer(report("first.js"), "visit", 1)
            executor.submit {}.get(5, TimeUnit.SECONDS)
            now = 3000
            cache.offer(report("first.js").copy(storage = mapOf("level" to "2")), "visit", 2)
            executor.submit {}.get(5, TimeUnit.SECONDS)
            assertEquals(1, requests.count { it == entry })
            now = 61000
            fail = false
            cache.offer(report("first.js").copy(storage = mapOf("level" to "3")), "visit", 3)
            executor.submit {}.get(5, TimeUnit.SECONDS)
            assertEquals(2, requests.count { it == entry })
            assertEquals("3", store.listGames().single().storage["level"])
        } finally {
            cache.setEnabled(false)
            executor.shutdownNow()
        }
    }

    @Test fun aNewerPendingGameRecordsItsPlayTimeBeforeAnOlderDownloadFinishes() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        var block = false
        val store =
            OfflineGameStore(
                temporary.newFolder(),
                AdResourceFilter(emptyList(), emptyList()),
                OfflineDownloader {
                        url,
                        target,
                        _
                    ->
                    if (block && url == entry) {
                        entered.countDown()
                        release.await(3, TimeUnit.SECONDS)
                    }
                    target.writeText("<!doctype html>")
                    OfflineDownloadMetadata("text/html", "utf-8", emptyMap())
                }
            )
        val newer = report().copy(entryUrl = entry.replace("app-42", "app-43"))
        store.save(report(), visitId = "old-first", playedAt = 10)
        store.save(newer, visitId = "old-second", playedAt = 20)
        val cache = AutomaticOfflineCache(store, executor)
        try {
            block = true
            cache.setEnabled(true)
            cache.offer(report(), "fresh-first", 100)
            assertTrue(entered.await(1, TimeUnit.SECONDS))
            cache.offer(newer, "fresh-second", 200)
            assertEquals(newer.entryUrl, store.listGames().first().entryUrl)
            assertEquals(200, store.listGames().first().lastPlayedAt)
        } finally {
            cache.setEnabled(false)
            release.countDown()
            executor.shutdownNow()
        }
    }

    @Test fun catalogueMetadataArrivingDuringASaveRefreshesAnOtherwiseIdenticalReport() {
        val requests = mutableListOf<String>()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        val artwork = "https://avatars.mds.yandex.net/get-games/42/cover/medium"
        val store =
            OfflineGameStore(
                temporary.newFolder(),
                AdResourceFilter(emptyList(), emptyList()),
                OfflineDownloader {
                        url,
                        target,
                        _
                    ->
                    requests += url
                    if (url == entry) {
                        entered.countDown()
                        release.await(3, TimeUnit.SECONDS)
                        target.writeText("<!doctype html>")
                        OfflineDownloadMetadata("text/html", "utf-8", emptyMap())
                    } else {
                        target.writeBytes(
                            java.util.Base64.getDecoder().decode(
                                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lE" +
                                    "QVR42mP8/x8AAusB9Y9Z4xkAAAAASUVORK5CYII="
                            )
                        )
                        OfflineDownloadMetadata("image/png", null, emptyMap())
                    }
                }
            )
        val cache = AutomaticOfflineCache(store, executor)
        try {
            cache.setEnabled(true)
            cache.offer(report(), "visit", 1)
            assertTrue(entered.await(1, TimeUnit.SECONDS))
            store.rememberCatalog(
                OfflineCatalogMetadata("42", "https://yandex.ru/games/app/42", "Космос", artwork)
            )
            cache.catalogChanged("42")
            release.countDown()
            executor.submit {}.get(5, TimeUnit.SECONDS)
            cache.offer(report(), "visit", 2)
            executor.submit {}.get(5, TimeUnit.SECONDS)
            assertEquals("Космос", store.listGames().single().title)
            assertTrue(store.listGames().single().cover != null)
            assertEquals(1, requests.count { it == entry })
            assertEquals(1, requests.count { it == artwork })
        } finally {
            release.countDown()
            cache.setEnabled(false)
            executor.shutdownNow()
        }
    }
}
