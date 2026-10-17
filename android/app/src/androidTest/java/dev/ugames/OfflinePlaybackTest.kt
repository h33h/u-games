package dev.ugames

import android.webkit.ServiceWorkerClient
import android.webkit.ServiceWorkerController
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import java.util.zip.GZIPOutputStream
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class OfflinePlaybackTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val entry = "https://app-42.cdn.games.yandex.net/offline-fixture/index.html"

    @Test fun offlineChromeClientRejectsPopupsBeforeTheyCanRestoreNetworkAccess() {
        val folder =
            File(instrumentation.targetContext.cacheDir, "offline-popup-${System.nanoTime()}")
        val store =
            OfflineGameStore(
                folder,
                AdResourceFilter(emptyList(), emptyList()),
                OfflineDownloader {
                        _,
                        target,
                        _
                    ->
                    target.writeText("<!doctype html>")
                    OfflineDownloadMetadata("text/html", "utf-8", emptyMap())
                }
            )
        val saved = store.save(
            OfflineCaptureReport(entry, "Fixture", emptyList(), emptyMap(), "{}", true)
        )
        val lease = requireNotNull(store.acquire(saved.id))
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity { activity ->
                    activity.connectivityChanged(false)
                    val view = ProtectedWebViewFactory.create(activity, offlineLease = lease)
                    activity.showWindow(view)
                    val message = android.os.Handler(
                        android.os.Looper.getMainLooper()
                    ).obtainMessage().apply {
                        obj = view.WebViewTransport()
                    }
                    assertFalse(view.webChromeClient!!.onCreateWindow(view, false, true, message))
                    assertTrue(view.settings.blockNetworkLoads)
                    val workers = ServiceWorkerController.getInstance()
                    assertTrue(workers.serviceWorkerWebSettings.blockNetworkLoads)
                }
            }
        } finally {
            lease.close()
            folder.deleteRecursively()
        }
    }

    @Test fun downloadedHtmlExecutesScriptsSdkAndDynamicResourcesWithNetworkDisabled() {
        val nonce = System.nanoTime()
        val entry = this.entry.replace("offline-fixture", "offline-sdk-fixture-$nonce")
        val progressKey = "ugames-test-fixture-level-$nonce"
        val context = instrumentation.targetContext
        val folder = File(context.cacheDir, "offline-fixture-${System.nanoTime()}")
        val resources = mapOf(
            entry to """
                <!doctype html><title>Offline fixture</title><p id="game">Игра</p>
                <script src="/sdk.js"></script><script type="module" src="module.js"></script>
                <script src="main.js?v=7"></script>
            """.trimIndent(),
            entry.substringBeforeLast('/') + "/main.js?v=7" to """
                (async () => {
                  const sdk = await YaGames.init();
                  const progress = localStorage.getItem(${JSONObject.quote(progressKey)});
                  const data = await fetch('levels.json').then(r => r.json());
                  const missing = await fetch('missing.json').then(r => r.status);
                  const external = await fetch('https://external.example/never-saved.json').then(r => r.status);
                  const module = await import('./module.js');
                  const late = document.createElement('script'); late.src = 'late.js';
                  late.onload = () => {
                    window.offlineResult = {progress, level:data.level, missing, external,
                      dynamic:window.dynamicResource, sdk:!!sdk.adv,
                      origin:location.origin, secure:isSecureContext, module:module.answer};
                  };
                  document.head.appendChild(late);
                })().catch(e => {window.offlineError=String(e)});
            """.trimIndent(),
            entry.substringBeforeLast('/') + "/levels.json" to "{\"level\":8}",
            entry.substringBeforeLast('/') + "/module.js" to
                "import {level} from './relative-module.js'; export const answer=level+1;",
            entry.substringBeforeLast('/') + "/relative-module.js" to "export const level=8;",
            entry.substringBeforeLast('/') + "/late.js" to "window.dynamicResource='loaded';"
        )
        val filter = AdResourceFilter(emptyList(), emptyList())
        val store = OfflineGameStore(
            folder,
            filter,
            OfflineDownloader { url, target, _ ->
                val compressed = url.endsWith("main.js?v=7")
                val brotli = url.endsWith("late.js")
                if (compressed) {
                    GZIPOutputStream(target.outputStream()).use {
                        it.write(resources.getValue(url).toByteArray())
                    }
                } else if (brotli) {
                    target.writeBytes(
                        "1b1f00a8a444769a90420c91448a5c4e55688286a805".chunked(2).map {
                            it.toInt(16).toByte()
                        }.toByteArray()
                    )
                } else {
                    target.writeText(resources.getValue(url))
                }
                OfflineDownloadMetadata(
                    if (url ==
                        entry
                    ) {
                        "text/html"
                    } else if (url.endsWith(".json")) {
                        "application/json"
                    } else {
                        "application/javascript"
                    },
                    "utf-8",
                    if (compressed ||
                        brotli
                    ) {
                        mapOf("Content-Encoding" to if (compressed) "gzip" else "br")
                    } else {
                        emptyMap()
                    }
                )
            }
        )
        try {
            val saved = store.save(
                OfflineCaptureReport(
                    entry,
                    "Fixture",
                    resources.keys.toList(),
                    mapOf(progressKey to "6"),
                    "{}",
                    true
                )
            )
            val lease = requireNotNull(store.acquire(saved.id))
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                seedOldServiceWorker(scenario)
                lateinit var view: WebView
                scenario.onActivity { activity ->
                    activity.connectivityChanged(false)
                    view = ProtectedWebViewFactory.create(activity, offlineLease = lease)
                    activity.showWindow(view)
                    ProtectedWebViewFactory.loadOfflineGame(view, lease.game)
                    assertTrue(view.settings.blockNetworkLoads)
                }
                val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(15)
                var result: JSONObject? = null
                var error = "null"
                while (System.nanoTime() < deadline) {
                    val raw = evaluate(view, "JSON.stringify(window.offlineResult || null)")
                    val decoded = org.json.JSONTokener(raw).nextValue()
                    error =
                        evaluate(
                            view,
                            "JSON.stringify({error:window.offlineError||null,preparation:window.__UGamesOfflinePreparationError||null,url:location.href,body:document.body?.innerText,scripts:[...document.scripts].map(s=>s.src),sdk:typeof window.YaGames})"
                        )
                    if (evaluate(view, "Boolean(window.__UGamesOfflinePreparationError)") ==
                        "true"
                    ) {
                        break
                    }
                    if (decoded is String && decoded != "null") {
                        result = JSONObject(decoded)
                        break
                    }
                    Thread.sleep(100)
                }
                assertTrue("Saved scripts run with blocked network; error=$error", result != null)
                assertEquals("6", result!!.getString("progress"))
                assertEquals(8, result.getInt("level"))
                assertEquals(9, result.getInt("module"))
                assertEquals(404, result.getInt("missing"))
                assertEquals(404, result.getInt("external"))
                assertEquals("loaded", result.getString("dynamic"))
                assertTrue(result.getBoolean("sdk"))
                assertTrue(result.getBoolean("secure"))
                assertEquals("https://app-42.cdn.games.yandex.net", result.getString("origin"))
                assertEquals("false", evaluate(view, "Boolean(window.oldWorkerRan)"))
                evaluate(view, "location.href = 'https://yandex.ru/games/'; true")
                Thread.sleep(200)
                scenario.onActivity { assertEquals(entry, view.url) }
            }
        } finally {
            folder.deleteRecursively()
        }
    }

    @Test fun normalAndErrorSurfacesHaveNoAddedNativeCacheControls() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val initial = allViews(activity.findViewById(android.R.id.content))
                assertTrue(initial.filterIsInstance<android.widget.ImageButton>().isEmpty())
                activity.showError("Fixture")
                assertEquals(
                    listOf("Попробовать снова", "В каталог"),
                    allViews(
                        activity.findViewById(android.R.id.content)
                    ).filterIsInstance<android.widget.Button>().map {
                        it.text.toString()
                    }
                )
            }
        }
    }

    @Test fun onlineRequestsNeverCreateACachePlaybackWebView() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.connectivityChanged(true)
                val saved =
                    SavedOfflineGame(
                        "a".repeat(64),
                        entry,
                        "Fixture",
                        0,
                        0,
                        emptyMap(),
                        "{}",
                        emptyMap()
                    )
                activity.openOfflineGame(saved)
                val view = allViews(
                    activity.findViewById(android.R.id.content)
                ).filterIsInstance<WebView>().single()
                assertFalse(view.settings.blockNetworkLoads)
                assertFalse(
                    ServiceWorkerController.getInstance().serviceWorkerWebSettings.blockNetworkLoads
                )
                assertEquals(
                    null,
                    view.webViewClient.shouldInterceptRequest(
                        view,
                        request(entry, mainFrame = true)
                    )
                )
            }
        }
    }

    @Test fun offlineStartupUsesTheNormalCatalogueAndReconnectRestoresTheNetwork() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var view: WebView
            scenario.onActivity { activity ->
                activity.connectivityChanged(false)
                view =
                    allViews(
                        activity.findViewById(android.R.id.content)
                    ).filterIsInstance<WebView>().single()
                assertTrue(view.settings.blockNetworkLoads)
            }
            view =
                waitForCurrent(
                    scenario,
                    "location.href === 'https://yandex.ru/games/' && " +
                        "document.readyState === 'complete' && " +
                        "Boolean(window.__UGamesCachedCatalog && !window.__UGamesOfflineConfig)"
                )
            scenario.onActivity {
                assertEquals(
                    404,
                    view.webViewClient.shouldInterceptRequest(
                        view,
                        request("https://external.example/never-network.json")
                    )!!.statusCode
                )
                assertTrue(
                    ServiceWorkerController.getInstance().serviceWorkerWebSettings.blockNetworkLoads
                )
            }
            scenario.onActivity { activity ->
                activity.connectivityChanged(true)
                val online = allViews(
                    activity.findViewById(android.R.id.content)
                ).filterIsInstance<WebView>().single()
                assertFalse(online.settings.blockNetworkLoads)
                assertEquals(
                    null,
                    online.webViewClient.shouldInterceptRequest(
                        online,
                        request(MainActivity.HOME, mainFrame = true)
                    )
                )
            }
        }
    }

    @Test fun ordinaryCatalogueCardsOpenTheCacheAndReconnectKeepsOfflineLocalProgress() {
        val root = File(instrumentation.targetContext.filesDir, "offline-games")
        val coverUrl = "https://avatars.mds.yandex.net/get-games/fixture/cover/medium"
        val cover = java.util.Base64.getDecoder().decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lE" +
                "QVR42mP8/x8AAusB9Y9Z4xkAAAAASUVORK5CYII="
        )
        val store =
            OfflineGameStore(
                root,
                AdResourceFilter(emptyList(), emptyList()),
                OfflineDownloader {
                        url,
                        target,
                        _
                    ->
                    if (url == coverUrl) {
                        target.writeBytes(cover)
                        OfflineDownloadMetadata("image/png", null, emptyMap())
                    } else {
                        target.writeText(
                            "<!doctype html><p id='fixture-game'>Fixture</p>" +
                                "<script>localStorage.setItem('offline-fixture-progress','9');</script>"
                        )
                        OfflineDownloadMetadata("text/html", "utf-8", emptyMap())
                    }
                }
            )
        store.rememberCatalog(
            OfflineCatalogMetadata("42", "https://yandex.ru/games/app/42", "Космос", coverUrl)
        )
        val saved = store.save(
            OfflineCaptureReport(entry, "New project", emptyList(), emptyMap(), "{}", true)
        )
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity { it.connectivityChanged(false) }
                val card = JSONObject.quote("a.game-card__link[href=\"$entry\"]")
                val catalog =
                    waitForCurrent(
                        scenario,
                        "Boolean(document.querySelector($card))"
                    )
                assertEquals(
                    "\"Космос\"",
                    evaluate(
                        catalog,
                        "document.querySelector($card).textContent"
                    )
                )
                scenario.onActivity {
                    val response = catalog.webViewClient.shouldInterceptRequest(
                        catalog,
                        request(saved.coverLocalUrl!!)
                    )!!
                    assertEquals(200, response.statusCode)
                    assertTrue(
                        response.data.use { stream ->
                            stream.readBytes().contentEquals(cover)
                        }
                    )
                    catalog.evaluateJavascript(
                        "document.querySelector($card).click();",
                        null
                    )
                }
                val offline =
                    waitForCurrent(scenario, "Boolean(document.getElementById('fixture-game'))")
                scenario.onActivity { assertTrue(offline.settings.blockNetworkLoads) }
                assertEquals(
                    "\"9\"",
                    evaluate(offline, "localStorage.getItem('offline-fixture-progress')")
                )
                scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }
                val backCatalogue =
                    waitForCurrent(scenario, "Boolean(document.querySelector($card))")
                scenario.onActivity {
                    backCatalogue.evaluateJavascript("document.querySelector($card).click();", null)
                }
                waitForCurrent(scenario, "Boolean(document.getElementById('fixture-game'))")
                lateinit var online: WebView
                scenario.onActivity { activity ->
                    activity.connectivityChanged(true)
                    online =
                        allViews(
                            activity.findViewById(android.R.id.content)
                        ).filterIsInstance<WebView>().single()
                    assertFalse(online.settings.blockNetworkLoads)
                    assertEquals(
                        null,
                        online.webViewClient.shouldInterceptRequest(
                            online,
                            request(entry, mainFrame = true)
                        )
                    )
                    online.stopLoading()
                    online.loadDataWithBaseURL(
                        entry,
                        "<!doctype html><p id='online-fixture'>Online</p>",
                        "text/html",
                        "utf-8",
                        null
                    )
                }
                waitForCurrent(scenario, "Boolean(document.getElementById('online-fixture'))")
                assertEquals(
                    "\"9\"",
                    evaluate(online, "localStorage.getItem('offline-fixture-progress')")
                )
                assertEquals("false", evaluate(online, "Boolean(window.__UGamesOfflineConfig)"))
            }
        } finally {
            store.delete(saved.id)
        }
    }

    @Test fun offlineCatalogueUnregistersAnOldPortalWorkerAndBlocksItsNetwork() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            seedOldServiceWorker(scenario, "https://yandex.ru")
            scenario.onActivity { it.connectivityChanged(false) }
            val catalog =
                waitForCurrent(
                    scenario,
                    "location.href === 'https://yandex.ru/games/' && " +
                        "document.readyState === 'complete' && Boolean(window.__UGamesCachedCatalog)"
                )
            assertEquals("false", evaluate(catalog, "Boolean(window.oldWorkerRan)"))
            scenario.onActivity {
                assertTrue(
                    ServiceWorkerController.getInstance().serviceWorkerWebSettings.blockNetworkLoads
                )
                assertEquals(
                    404,
                    catalog.webViewClient.shouldInterceptRequest(
                        catalog,
                        request("https://external.example/never-network.json")
                    )!!.statusCode
                )
            }
        }
    }

    @Test fun aHeldCatalogueIndexOpensTheNewPublishedDirectoryAfterFreshRefresh() {
        val entry = this.entry.replace("offline-fixture", "held-refresh-fixture")
        val folder = File(instrumentation.targetContext.filesDir, "offline-games")
        var revision = 1
        val script = entry.substringBeforeLast('/') + "/refresh.js"
        val store =
            OfflineGameStore(
                folder,
                AdResourceFilter(emptyList(), emptyList()),
                OfflineDownloader {
                        url,
                        target,
                        _
                    ->
                    target.writeText(
                        if (url ==
                            entry
                        ) {
                            "<!doctype html><script src='refresh.js'></script>"
                        } else {
                            "window.snapshotRevision=$revision;"
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
        val report = OfflineCaptureReport(entry, "Fixture", listOf(script), emptyMap(), "{}", true)
        val heldIndex = store.save(report, visitId = "old-visit")
        revision = 2
        store.save(report, visitId = "fresh-visit")
        assertFalse(heldIndex.resource(entry)!!.file.exists())
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity { activity ->
                    activity.connectivityChanged(false)
                    activity.openOfflineGame(heldIndex)
                }
                val view = waitForCurrent(scenario, "window.snapshotRevision === 2")
                scenario.onActivity { assertTrue(view.settings.blockNetworkLoads) }
            }
        } finally {
            store.delete(heldIndex.id)
        }
    }

    @Test fun aHeldCatalogueIndexIncludesResourcesAddedDuringTheSameVisit() {
        val entry = this.entry.replace("offline-fixture", "held-extension-fixture")
        val folder = File(instrumentation.targetContext.filesDir, "offline-games")
        val late = entry.substringBeforeLast('/') + "/new-level.json"
        val store =
            OfflineGameStore(
                folder,
                AdResourceFilter(emptyList(), emptyList()),
                OfflineDownloader {
                        url,
                        target,
                        _
                    ->
                    target.writeText(
                        if (url == entry) {
                            "<!doctype html><script>fetch('new-level.json').then(r=>r.json())" +
                                ".then(data=>window.snapshotRevision=data.level)" +
                                ".catch(()=>window.snapshotRevision=-1);</script>"
                        } else {
                            "{\"level\":2}"
                        }
                    )
                    OfflineDownloadMetadata(
                        if (url ==
                            entry
                        ) {
                            "text/html"
                        } else {
                            "application/json"
                        },
                        "utf-8",
                        emptyMap()
                    )
                }
            )
        val report = OfflineCaptureReport(entry, "Fixture", emptyList(), emptyMap(), "{}", true)
        val heldIndex = store.save(report, visitId = "same-visit")
        store.save(report.copy(resources = listOf(late)), visitId = "same-visit")
        assertTrue(heldIndex.resource(entry)!!.file.exists())
        assertEquals(null, heldIndex.resource(late))
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity { activity ->
                    activity.connectivityChanged(false)
                    activity.openOfflineGame(heldIndex)
                }
                val view = waitForCurrent(scenario, "window.snapshotRevision === 2")
                scenario.onActivity { assertTrue(view.settings.blockNetworkLoads) }
            }
        } finally {
            store.delete(heldIndex.id)
        }
    }

    private fun waitForCurrent(
        scenario: ActivityScenario<MainActivity>,
        expression: String
    ): WebView {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
        while (System.nanoTime() < deadline) {
            var candidate: WebView? = null
            val ready = CountDownLatch(1)
            var result: String? = null
            scenario.onActivity { activity ->
                candidate =
                    allViews(
                        activity.findViewById(android.R.id.content)
                    ).filterIsInstance<WebView>().lastOrNull()
                candidate?.evaluateJavascript(expression) {
                    result = it
                    ready.countDown()
                }
            }
            ready.await(500, TimeUnit.MILLISECONDS)
            if (result == "true" && candidate != null) return candidate!!
            Thread.sleep(50)
        }
        throw AssertionError("Expected WebView surface: $expression")
    }

    private fun request(url: String, mainFrame: Boolean = false) = object : WebResourceRequest {
        override fun getUrl() = android.net.Uri.parse(url)
        override fun isForMainFrame() = mainFrame
        override fun isRedirect() = false
        override fun hasGesture() = false
        override fun getMethod() = "GET"
        override fun getRequestHeaders() = emptyMap<String, String>()
    }

    private fun seedOldServiceWorker(
        scenario: ActivityScenario<MainActivity>,
        origin: String = "https://app-42.cdn.games.yandex.net"
    ) {
        lateinit var view: WebView
        val worker = """
            self.addEventListener('install', () => self.skipWaiting());
            self.addEventListener('activate', event => event.waitUntil(clients.claim()));
            self.addEventListener('fetch', event => event.respondWith(new Response(
              '<!doctype html><script>window.oldWorkerRan=true;</script>',
              {headers:{'Content-Type':'text/html'}})));
        """.trimIndent()
        val seed = """
            <!doctype html><script>
            navigator.serviceWorker.register('/offline-worker.js', {scope:'/'})
              .then(() => navigator.serviceWorker.ready)
              .then(() => {window.workerInstalled=true;})
              .catch(error => {window.workerInstallError=String(error);});
            </script>
        """.trimIndent()
        scenario.onActivity { activity ->
            fun response(request: WebResourceRequest): WebResourceResponse? =
                when (request.url.path) {
                    "/offline-worker.js" -> WebResourceResponse(
                        "application/javascript",
                        "utf-8",
                        worker.byteInputStream()
                    )

                    "/worker-seed.html" -> WebResourceResponse(
                        "text/html",
                        "utf-8",
                        seed.byteInputStream()
                    )

                    else -> null
                }
            ServiceWorkerController.getInstance().apply {
                serviceWorkerWebSettings.blockNetworkLoads = false
                setServiceWorkerClient(object : ServiceWorkerClient() {
                    override fun shouldInterceptRequest(request: WebResourceRequest) =
                        response(request)
                })
            }
            view = WebView(activity).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                webViewClient = object : WebViewClient() {
                    override fun shouldInterceptRequest(
                        view: WebView,
                        request: WebResourceRequest
                    ) = response(request)
                }
            }
            activity.showWindow(view)
            view.loadUrl("$origin/worker-seed.html")
        }
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
        while (System.nanoTime() < deadline &&
            evaluate(view, "Boolean(window.workerInstalled)") != "true"
        ) {
            if (evaluate(view, "Boolean(window.workerInstallError)") == "true") break
            Thread.sleep(50)
        }
        assertEquals(
            "Worker fixture installs: " + evaluate(view, "window.workerInstallError || null"),
            "true",
            evaluate(view, "Boolean(window.workerInstalled)")
        )
        scenario.onActivity { view.loadUrl("$origin/old-worker-probe") }
        val probeDeadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (System.nanoTime() < probeDeadline &&
            evaluate(view, "Boolean(window.oldWorkerRan)") != "true"
        ) {
            Thread.sleep(50)
        }
        assertEquals(
            "Old worker controls navigations before offline launch",
            "true",
            evaluate(view, "Boolean(window.oldWorkerRan)")
        )
    }

    private fun allViews(view: android.view.View): List<android.view.View> = listOf(view) +
        if (view is android.view.ViewGroup) {
            (0 until view.childCount).flatMap {
                allViews(view.getChildAt(it))
            }
        } else {
            emptyList()
        }

    private fun evaluate(view: WebView, script: String): String {
        val value = AtomicReference<String>()
        val latch = CountDownLatch(1)
        instrumentation.runOnMainSync {
            view.evaluateJavascript(script) {
                value.set(it)
                latch.countDown()
            }
        }
        assertTrue(latch.await(5, TimeUnit.SECONDS))
        return value.get()
    }
}
