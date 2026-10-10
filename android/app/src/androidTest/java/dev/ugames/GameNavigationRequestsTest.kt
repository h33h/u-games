package dev.ugames

import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GameNavigationRequestsTest {
    @Test fun realFetchAndXhrPostRequestsRemainAvailable() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val blocked = AtomicBoolean(false)
        val posts = AtomicInteger(0)
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var view: WebView
            scenario.onActivity { activity ->
                view = ProtectedWebViewFactory.create(activity)
                val productionClient = view.webViewClient
                view.webViewClient = object : WebViewClient() {
                    override fun shouldInterceptRequest(
                        v: WebView,
                        request: WebResourceRequest
                    ): WebResourceResponse? {
                        val response = productionClient.shouldInterceptRequest(v, request)
                        if (request.url.host != "api.fixture.test") return response
                        if (request.method == "POST") posts.incrementAndGet()
                        if (response != null) blocked.set(true)
                        return WebResourceResponse(
                            "text/plain",
                            "utf-8",
                            200,
                            "OK",
                            mapOf(
                                "Access-Control-Allow-Origin" to "*",
                                "Access-Control-Allow-Methods" to "POST, OPTIONS"
                            ),
                            "ok".byteInputStream()
                        )
                    }
                }
                activity.showWindow(view)
                view.loadDataWithBaseURL(
                    MainActivity.HOME,
                    """
                    <script>
                    const url = 'https://api.fixture.test/save';
                    Promise.all([
                      fetch(url, {method:'POST', body:'progress=1'}).then(r => r.text()),
                      new Promise((resolve, reject) => {
                        const xhr = new XMLHttpRequest();
                        xhr.open('POST', url);
                        xhr.onload = () => resolve(xhr.responseText);
                        xhr.onerror = reject;
                        xhr.send('progress=1');
                      })
                    ]).then(results => { window.apiResult = results.every(r => r === 'ok'); })
                      .catch(() => { window.apiResult = false; });
                    </script>
                    """.trimIndent(),
                    "text/html",
                    "utf-8",
                    null
                )
            }
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
            var result = "null"
            while (System.nanoTime() < deadline) {
                val received = CountDownLatch(1)
                val value = AtomicReference("null")
                instrumentation.runOnMainSync {
                    view.evaluateJavascript("window.apiResult") {
                        value.set(it)
                        received.countDown()
                    }
                }
                assertTrue(received.await(5, TimeUnit.SECONDS))
                result = value.get()
                if (result == "true" || result == "false") break
                Thread.sleep(100)
            }
            assertEquals("true", result)
            assertEquals(2, posts.get())
            assertFalse("Game API POSTs must not be treated as document navigation", blocked.get())
        }
    }
}
