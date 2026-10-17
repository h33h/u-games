package dev.ugames

import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.widget.Button
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.webkit.WebViewCompat
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class OfflineFailureTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    @Test fun cachedLoadAndHttpFailuresReturnToTheCatalogueWithoutErrorControls() {
        val fixture = fixture("load-http")
        val key = "ugames-test-progress-${System.nanoTime()}"
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                val first = open(scenario, fixture.game)
                evaluate(first, "localStorage.setItem(${JSONObject.quote(key)},'9'); true")
                scenario.onActivity { it.pageLoadFailed(first, "Cache load failure") }
                val catalog = catalogue(scenario)
                assertNoNativeError(scenario)
                assertEquals(
                    "0",
                    evaluate(catalog, "document.querySelectorAll(${card(fixture.game)}).length")
                )
                scenario.onActivity { it.openOfflineGame(fixture.game) }
                catalogue(scenario, excluding = catalog)
                assertNoNativeError(scenario)
                scenario.onActivity { it.connectivityChanged(true) }
                val refreshed = fixture.store.save(fixture.report, visitId = "fresh")
                val second = open(scenario, refreshed)
                assertEquals(
                    "\"9\"",
                    evaluate(second, "localStorage.getItem(${JSONObject.quote(key)})")
                )
                scenario.onActivity { it.pageHttpFailed(second, "Cache HTTP failure") }
                val recovered = catalogue(scenario)
                assertNoNativeError(scenario)
                assertEquals(
                    "0",
                    evaluate(recovered, "document.querySelectorAll(${card(refreshed)}).length")
                )
            }
        } finally {
            fixture.store.delete(fixture.game.id)
        }
    }

    @Test fun preparationFailureReturnsQuietlyToTheCatalogue() {
        val fixture = fixture("preparation")
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                val view = open(scenario, fixture.game)
                scenario.onActivity {
                    view.evaluateJavascript(
                        "window.__UGamesProtection.offlinePreparationFailed();",
                        null
                    )
                }
                catalogue(scenario)
                assertNoNativeError(scenario)
            }
        } finally {
            fixture.store.delete(fixture.game.id)
        }
    }

    @Test fun aManifestListedResourceLostDuringReplayReturnsQuietlyToTheCatalogue() {
        val fixture = fixture("lost-resource", listed = true)
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                val view = open(scenario, fixture.game)
                fixture.game.resource(fixture.listedUrl)!!.file.delete()
                scenario.onActivity {
                    view.evaluateJavascript(
                        "const late=document.createElement('script');" +
                            "late.src='listed.js';document.body.appendChild(late);",
                        null
                    )
                }
                catalogue(scenario)
                assertNoNativeError(scenario)
            }
        } finally {
            fixture.store.delete(fixture.game.id)
        }
    }

    @Test fun aCorruptCompressedSubresourceReturnsQuietlyToTheCatalogue() {
        val entry = "https://app-42.cdn.games.yandex.net/cache-failure-gzip/index.html"
        val script = entry.substringBeforeLast('/') + "/listed.js"
        val store =
            OfflineGameStore(
                File(instrumentation.targetContext.filesDir, "offline-games"),
                AdResourceFilter(emptyList(), emptyList()),
                OfflineDownloader {
                        url,
                        target,
                        _
                    ->
                    if (url == entry) {
                        target.writeText("<!doctype html><p id='cache-fixture'>Game</p>")
                    } else {
                        java.util.zip.GZIPOutputStream(target.outputStream()).use {
                            it.write("window.listedResourceLoaded=true;".toByteArray())
                        }
                    }
                    OfflineDownloadMetadata(
                        if (url ==
                            entry
                        ) {
                            "text/html"
                        } else {
                            "application/javascript"
                        },
                        "utf-8",
                        if (url ==
                            entry
                        ) {
                            emptyMap()
                        } else {
                            mapOf("Content-Encoding" to "gzip")
                        }
                    )
                }
            )
        val game = store.save(
            OfflineCaptureReport(entry, "Fixture", listOf(script), emptyMap(), "{}", true)
        )
        val resource = game.resource(script)!!
        val damaged = resource.file.readBytes()
        damaged[damaged.size - 8] = (damaged[damaged.size - 8].toInt() xor 1).toByte()
        resource.file.writeBytes(damaged)
        assertEquals(resource.size, resource.file.length())
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                val view = open(scenario, game)
                scenario.onActivity {
                    view.evaluateJavascript(
                        "const late=document.createElement('script');late.src='listed.js';document.body.appendChild(late);",
                        null
                    )
                }
                catalogue(scenario)
                assertNoNativeError(scenario)
            }
        } finally {
            store.delete(game.id)
        }
    }

    @Test fun cataloguePreparationFailureUsesTheProtectedLocalShellOnce() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var view: WebView
            val key = "ugames-test-preparation-${System.nanoTime()}"
            scenario.onActivity { activity ->
                activity.connectivityChanged(false)
                view = ProtectedWebViewFactory.create(activity, cachedCatalog = emptyList())
                WebViewCompat.addDocumentStartJavaScript(
                    view,
                    "if(location.pathname.includes('offline-bootstrap')){" +
                        "navigator.serviceWorker.getRegistrations=function(){" +
                        "localStorage.setItem(${JSONObject.quote(key)}," +
                        "String(Number(localStorage.getItem(${JSONObject.quote(key)})||0)+1));" +
                        "return Promise.reject(new Error('fixture unavailable'));};}",
                    setOf("https://yandex.ru")
                )
                activity.showWindow(view)
                ProtectedWebViewFactory.loadOfflineCatalog(view)
            }
            val recovered = catalogue(scenario)
            assertEquals(
                "\"1\"",
                evaluate(recovered, "localStorage.getItem(${JSONObject.quote(key)})")
            )
            scenario.onActivity {
                assertTrue(recovered.settings.blockNetworkLoads)
                recovered.evaluateJavascript(
                    "window.__UGamesProtection.offlinePreparationFailed();",
                    null
                )
            }
            catalogue(scenario)
            assertNoNativeError(scenario)
            assertEquals(
                "\"1\"",
                evaluate(recovered, "localStorage.getItem(${JSONObject.quote(key)})")
            )
        }
    }

    @Test fun staleCachedPreparationCallbackCannotReplaceAnOnlineError() {
        val fixture = fixture("stale-callback")
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                val cached = open(scenario, fixture.game)
                scenario.onActivity { activity ->
                    activity.connectivityChanged(true)
                    val online = allViews(
                        activity.findViewById(android.R.id.content)
                    ).filterIsInstance<WebView>().single()
                    activity.pageHttpFailed(online, "Online service failure")
                    activity.offlinePreparationFailed(cached)
                    val views = allViews(activity.findViewById(android.R.id.content))
                    assertEquals(
                        listOf("Попробовать снова", "В каталог"),
                        views.filterIsInstance<Button>().map {
                            it.text.toString()
                        }
                    )
                    assertTrue(
                        views.filterIsInstance<TextView>().any {
                            it.text.toString() ==
                                "Online service failure"
                        }
                    )
                }
            }
        } finally {
            fixture.store.delete(fixture.game.id)
        }
    }

    @Test fun missingSnapshotEntryAndTruncatedResourceNeverOpenAnErrorSurface() {
        for (damage in listOf("snapshot", "entry", "resource")) {
            val fixture = fixture("missing-$damage", listed = true)
            try {
                when (damage) {
                    "snapshot" -> fixture.game.resource(
                        fixture.game.entryUrl
                    )!!.file.parentFile!!.deleteRecursively()

                    "entry" -> fixture.game.resource(fixture.game.entryUrl)!!.file.delete()

                    else -> fixture.game.resource(
                        fixture.listedUrl
                    )!!.file.writeBytes(byteArrayOf(1))
                }
                ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                    scenario.onActivity { activity ->
                        activity.connectivityChanged(false)
                        activity.openOfflineGame(fixture.game)
                    }
                    catalogue(scenario)
                    assertNoNativeError(scenario)
                }
            } finally {
                fixture.store.delete(fixture.game.id)
            }
        }
    }

    @Test fun failedBackgroundQuotaAndDownloadsLeaveTheActiveGameAndProgressUntouched() {
        val folder =
            File(instrumentation.targetContext.cacheDir, "cache-background-${System.nanoTime()}")
        val entry = "https://app-42.cdn.games.yandex.net/cache-background/index.html"
        val fail = java.util.concurrent.atomic.AtomicBoolean(false)
        val store =
            OfflineGameStore(
                folder,
                AdResourceFilter(emptyList(), emptyList()),
                OfflineDownloader {
                        url,
                        target,
                        maximum
                    ->
                    if (url == entry) {
                        target.writeText("<!doctype html><p id='cache-fixture'>Game</p>")
                    } else {
                        if (fail.get()) throw java.io.IOException("fixture download unavailable")
                        target.writeBytes(ByteArray(maximum.toInt()))
                    }
                    OfflineDownloadMetadata("text/html", "utf-8", emptyMap())
                },
                maxCacheBytes = 4096
            )
        val game = store.save(
            OfflineCaptureReport(entry, "Fixture", emptyList(), emptyMap(), "{}", true)
        )
        val lease = requireNotNull(store.acquire(game.id))
        val executor = java.util.concurrent.Executors.newSingleThreadExecutor()
        val cache = AutomaticOfflineCache(store, executor)
        val key = "ugames-test-background-${System.nanoTime()}"
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity { activity ->
                    activity.connectivityChanged(false)
                    val view = ProtectedWebViewFactory.create(activity, offlineLease = lease)
                    activity.showWindow(view)
                    ProtectedWebViewFactory.loadOfflineGame(view, lease.game)
                }
                val active = waitFor(scenario, "Boolean(document.getElementById('cache-fixture'))")
                evaluate(active, "localStorage.setItem(${JSONObject.quote(key)},'9'); true")
                cache.setEnabled(true)
                val report =
                    OfflineCaptureReport(
                        entry.replace("app-42", "app-43"),
                        "Other",
                        emptyList(),
                        emptyMap(),
                        "{}",
                        true
                    )
                cache.offer(report, "quota", 100)
                executor.submit {}.get(5, TimeUnit.SECONDS)
                fail.set(true)
                cache.offer(report, "download", 101)
                executor.submit {}.get(5, TimeUnit.SECONDS)
                assertEquals(
                    "\"9\"",
                    evaluate(active, "localStorage.getItem(${JSONObject.quote(key)})")
                )
                assertEquals(
                    "true",
                    evaluate(active, "Boolean(document.getElementById('cache-fixture'))")
                )
                assertTrue(game.resource(entry)!!.file.exists())
                assertTrue(folder.walkTopDown().filter { it.isFile }.sumOf { it.length() } <= 4096)
                assertNoNativeError(scenario)
            }
        } finally {
            cache.setEnabled(false)
            executor.shutdownNow()
            lease.close()
            folder.deleteRecursively()
        }
    }

    private fun card(game: SavedOfflineGame) =
        JSONObject.quote("a.game-card__link[href=\"${game.entryUrl}\"]")

    private data class Fixture(
        val store: OfflineGameStore,
        val game: SavedOfflineGame,
        val listedUrl: String,
        val report: OfflineCaptureReport
    )

    private fun fixture(name: String, listed: Boolean = false): Fixture {
        val entry = "https://app-42.cdn.games.yandex.net/cache-failure-$name/index.html"
        val script = entry.substringBeforeLast('/') + "/listed.js"
        val store = OfflineGameStore(
            File(instrumentation.targetContext.filesDir, "offline-games"),
            AdResourceFilter(emptyList(), emptyList()),
            OfflineDownloader { url, target, _ ->
                target.writeText(
                    if (url ==
                        entry
                    ) {
                        "<!doctype html><p id='cache-fixture'>Game</p>"
                    } else {
                        "window.listedResourceLoaded=true;"
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
            }
        )
        val report =
            OfflineCaptureReport(
                entry,
                "Fixture",
                if (listed) listOf(script) else emptyList(),
                emptyMap(),
                "{}",
                true
            )
        return Fixture(store, store.save(report), script, report)
    }

    private fun open(scenario: ActivityScenario<MainActivity>, game: SavedOfflineGame): WebView {
        scenario.onActivity { activity ->
            activity.connectivityChanged(false)
            activity.openOfflineGame(game)
        }
        return waitFor(scenario, "Boolean(document.getElementById('cache-fixture'))")
    }

    private fun catalogue(scenario: ActivityScenario<MainActivity>, excluding: WebView? = null) =
        waitFor(
            scenario,
            "location.href==='https://yandex.ru/games/' && Boolean(document.querySelector('main.ugames-cached-main'))",
            excluding
        )

    private fun assertNoNativeError(scenario: ActivityScenario<MainActivity>) {
        scenario.onActivity { activity ->
            val views = allViews(activity.findViewById(android.R.id.content))
            assertTrue(views.filterIsInstance<Button>().isEmpty())
            assertTrue(views.filterIsInstance<TextView>().filter { it !is Button }.isEmpty())
        }
    }

    private fun waitFor(
        scenario: ActivityScenario<MainActivity>,
        expression: String,
        excluding: WebView? = null
    ): WebView {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(8)
        while (System.nanoTime() < deadline) {
            val ready = CountDownLatch(1)
            var candidate: WebView? = null
            val result = AtomicReference<String>()
            scenario.onActivity { activity ->
                candidate =
                    allViews(
                        activity.findViewById(android.R.id.content)
                    ).filterIsInstance<WebView>().lastOrNull()
                candidate?.takeIf { it !== excluding }?.evaluateJavascript(expression) {
                    result.set(it)
                    ready.countDown()
                }
            }
            ready.await(200, TimeUnit.MILLISECONDS)
            if (result.get() == "true" && candidate != null) return candidate!!
            Thread.sleep(50)
        }
        throw AssertionError("Expected ordinary surface: $expression")
    }

    private fun evaluate(view: WebView, script: String): String {
        val ready = CountDownLatch(1)
        val result = AtomicReference<String>()
        instrumentation.runOnMainSync {
            view.evaluateJavascript(script) {
                result.set(it)
                ready.countDown()
            }
        }
        assertTrue(ready.await(5, TimeUnit.SECONDS))
        return result.get()
    }

    private fun allViews(view: View): List<View> = listOf(view) + if (view is ViewGroup) {
        (0 until view.childCount).flatMap { allViews(view.getChildAt(it)) }
    } else {
        emptyList()
    }
}
