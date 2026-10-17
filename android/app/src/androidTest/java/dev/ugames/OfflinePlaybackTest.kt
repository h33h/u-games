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
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
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
                val view = ProtectedWebViewFactory.create(activity, offlineGame = saved)
                activity.showWindow(view)
                val message = android.os.Handler(
                    android.os.Looper.getMainLooper()
                ).obtainMessage().apply {
                    obj = view.WebViewTransport()
                }
                assertFalse(view.webChromeClient!!.onCreateWindow(view, false, true, message))
                assertTrue(view.settings.blockNetworkLoads)
                val workers = android.webkit.ServiceWorkerController.getInstance()
                assertTrue(workers.serviceWorkerWebSettings.blockNetworkLoads)
            }
        }
    }

    @Test fun downloadedHtmlExecutesScriptsSdkAndDynamicResourcesWithNetworkDisabled() {
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
                  const progress = localStorage.getItem('fixture-level');
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
                    mapOf("fixture-level" to "6"),
                    "{}",
                    true
                )
            )
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                seedOldServiceWorker(scenario)
                lateinit var view: WebView
                scenario.onActivity { activity ->
                    activity.openOfflineGame(saved)
                    view =
                        allViews(
                            activity.findViewById(android.R.id.content)
                        ).filterIsInstance<WebView>().single()
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

    private fun seedOldServiceWorker(scenario: ActivityScenario<MainActivity>) {
        lateinit var view: WebView
        val origin = "https://app-42.cdn.games.yandex.net"
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
