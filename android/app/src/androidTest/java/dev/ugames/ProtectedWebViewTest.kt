package dev.ugames

import android.app.Activity
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ProtectedWebViewTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    @Test fun draggingMenuDoesNotClickAndRestoresPositionAfterResize() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val suite = "menu-test-${java.util.UUID.randomUUID()}"
                val context = object : android.content.ContextWrapper(activity) {
                    override fun getSharedPreferences(name: String, mode: Int) =
                        activity.getSharedPreferences(suite, mode)
                }
                val preferences = context.getSharedPreferences("gameMenu", 0)
                try {
                    val container = android.widget.FrameLayout(context)
                    container.setPadding(30, 60, 30, 20)
                    val button = FloatingMenuButton(context)
                    container.addView(button)
                    container.layout(0, 0, 400, 800)
                    button.layout(0, 0, 48, 48)
                    button.place()
                    var clicks = 0
                    button.setOnClickListener { clicks++ }
                    fun touch(action: Int, x: Float, y: Float) {
                        val event = android.view.MotionEvent.obtain(0, 0, action, x, y, 0)
                        button.onTouchEvent(event)
                        event.recycle()
                    }
                    touch(android.view.MotionEvent.ACTION_DOWN, 200f, 200f)
                    touch(android.view.MotionEvent.ACTION_MOVE, -1000f, -1000f)
                    touch(android.view.MotionEvent.ACTION_UP, -1000f, -1000f)
                    assertEquals(0, clicks)
                    assertEquals(0f, preferences.getFloat("x", -1f), 0.01f)
                    assertEquals(0f, preferences.getFloat("y", -1f), 0.01f)
                    val restored = FloatingMenuButton(context)
                    container.addView(restored)
                    container.layout(0, 0, 800, 400)
                    button.place()
                    restored.layout(0, 0, 48, 48)
                    restored.place()
                    assertEquals(button.x, restored.x, 0.01f)
                    assertEquals(button.y, restored.y, 0.01f)
                    assertTrue(restored.x >= 30)
                    assertTrue(restored.y >= 60)
                    assertTrue(restored.x + restored.width <= 770)
                    assertTrue(restored.y + restored.height <= 380)
                    touch(android.view.MotionEvent.ACTION_DOWN, 20f, 20f)
                    touch(android.view.MotionEvent.ACTION_UP, 20f, 20f)
                    assertEquals(1, clicks)
                } finally {
                    preferences.edit().clear().commit()
                }
            }
        }
    }

    @Test fun fullscreenMenuStaysAboveGameAndSurvivesPopupChanges() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val root = activity.findViewById<android.view.ViewGroup>(android.R.id.content)
                val menu = allViews(root).single { it.contentDescription == "Меню" }
                val popup = ProtectedWebViewFactory.create(activity)
                activity.showWindow(popup)
                assertTrue(menu.isAttachedToWindow)
                assertTrue(popup.isAttachedToWindow)
                assertTrue(menu.parent !== popup.parent)
                activity.closeWindow(popup)
                assertTrue(menu.isAttachedToWindow)
            }
        }
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
        assertTrue("JavaScript response", latch.await(5, TimeUnit.SECONDS))
        return value.get()
    }

    private fun exerciseFixture(reload: Boolean = false, popup: Boolean = false) {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var view: WebView
            scenario.onActivity { activity ->
                view = ProtectedWebViewFactory.create(activity)
                val parentClient = view.webViewClient
                view.webViewClient = object : WebViewClient() {
                    override fun shouldInterceptRequest(
                        v: WebView,
                        request: WebResourceRequest
                    ): WebResourceResponse? {
                        if (request.url.host !in
                            listOf("fixture.ugames.test", "child.fixture.ugames.test")
                        ) {
                            return parentClient.shouldInterceptRequest(v, request)
                        }
                        val name = request.url.lastPathSegment ?: return null
                        return if (name in listOf("sdk-lifecycle.html", "frame.html")) {
                            val html = instrumentation.context.assets.open(
                                name
                            ).bufferedReader().use {
                                it.readText()
                            }
                                .replace(
                                    "src=\"frame.html\"",
                                    "src=\"https://child.fixture.ugames.test/frame.html\""
                                )
                            WebResourceResponse("text/html", "utf-8", html.byteInputStream())
                        } else {
                            WebResourceResponse(
                                "text/plain",
                                "utf-8",
                                java.io.ByteArrayInputStream(ByteArray(0))
                            )
                        }
                    }
                    override fun onRenderProcessGone(
                        v: WebView,
                        detail: android.webkit.RenderProcessGoneDetail
                    ): Boolean = parentClient.onRenderProcessGone(v, detail)
                }
                activity.showWindow(view)
                view.loadUrl("https://fixture.ugames.test/sdk-lifecycle.html")
            }
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(15)
            var result: JSONObject? = null
            while (System.nanoTime() < deadline) {
                val raw = evaluate(view, "JSON.stringify(window.fixtureResult || null)")
                val decoded = org.json.JSONTokener(raw).nextValue()
                if (decoded is String && decoded != "null") {
                    val candidate = JSONObject(decoded)
                    if (candidate.optJSONObject("child")?.optInt("closes") == 1 &&
                        candidate.optInt("closes") == 1
                    ) {
                        result = candidate
                        break
                    }
                }
                Thread.sleep(100)
            }
            assertNotNull("Both protected frames complete their request", result)
            assertTrue(result!!.getBoolean("early"))
            assertEquals(0, result.getInt("original"))
            assertEquals(1, result.getInt("rewards"))
            assertEquals(1, result.getInt("fullscreen"))
            assertEquals(
                "A closed social advertising shadow is dismissed",
                1,
                result.getInt("shadowClosed")
            )
            assertEquals("Encapsulation is preserved", "closed", result.getString("shadowMode"))
            assertEquals(
                "Non-advertising components are untouched",
                0,
                result.getInt("innocentClosed")
            )
            assertEquals(
                "Obfuscated portal advertisements are dismissed",
                1,
                result.getInt("obfuscatedClosed")
            )
            assertTrue(
                "Salted banners retain their advertising marker",
                result.getBoolean("saltedBannerHidden")
            )
            assertTrue(result.getJSONObject("child").getBoolean("early"))
            assertEquals(0, result.getJSONObject("child").getInt("original"))
            assertEquals(1, result.getJSONObject("child").getInt("rewards"))
            if (reload) {
                instrumentation.runOnMainSync {
                    view.onPause()
                    view.onResume()
                }
                assertEquals(
                    1,
                    JSONObject(
                        org.json.JSONTokener(
                            evaluate(view, "JSON.stringify(window.fixtureResult)")
                        ).nextValue() as String
                    ).getInt("rewards")
                )
            }
            if (popup) {
                val windowCreated = CountDownLatch(1)
                instrumentation.runOnMainSync {
                    val actual = view.webChromeClient
                    val fixtureClient = view.webViewClient
                    view.webChromeClient = object : android.webkit.WebChromeClient() {
                        override fun onCreateWindow(
                            parent: WebView,
                            dialog: Boolean,
                            gesture: Boolean,
                            msg: android.os.Message
                        ): Boolean {
                            val accepted = actual!!.onCreateWindow(parent, dialog, gesture, msg)
                            if (accepted) {
                                val child =
                                    requireNotNull((msg.obj as WebView.WebViewTransport).webView)
                                child.webViewClient = fixtureClient
                                windowCreated.countDown()
                            }
                            return accepted
                        }
                    }
                }
                evaluate(
                    view,
                    "window.popup = window.open('https://fixture.ugames.test/sdk-lifecycle.html'); Boolean(window.popup)"
                )
                assertTrue(
                    "Production ChromeClient creates the protected child",
                    windowCreated.await(5, TimeUnit.SECONDS)
                )
                val limit = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
                var early = "false"
                while (System.nanoTime() < limit) {
                    early =
                        evaluate(
                            view,
                            "Boolean(window.popup && window.popup.fixtureResult && window.popup.fixtureResult.early && window.popup.fixtureResult.rewards === 1)"
                        )
                    if (early == "true") break
                    Thread.sleep(100)
                }
                assertEquals("A navigated popup receives protection before its SDK", "true", early)
            }
            scenario.onActivity { activity -> activity.closeWindow(view) }
        }
    }

    @Test fun documentStartAdapterProtectsMainFrameAndChild() = exerciseFixture()

    @Test fun returningFromBackgroundDoesNotReplayReward() = exerciseFixture(true)

    @Test fun popupUsesProtectedFactory() = exerciseFixture(popup = true)

    @Test fun backClosesPopupWithoutNavigatingParent() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val popup = ProtectedWebViewFactory.create(activity)
                activity.showWindow(popup)
                assertTrue(popup.isAttachedToWindow)
                activity.onBackPressedDispatcher.onBackPressed()
                assertFalse(popup.isAttachedToWindow)
            }
        }
    }

    @Test fun unsupportedDocumentStartDoesNotLoadGame() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                assertThrows(UnsupportedOperationException::class.java) {
                    ProtectedWebViewFactory.create(activity, supportsDocumentStart = false)
                }
            }
        }
    }

    private fun allViews(root: android.view.View): List<android.view.View> {
        val result = mutableListOf(root)
        if (root is android.view.ViewGroup) {
            for (index in 0 until root.childCount) result.addAll(allViews(root.getChildAt(index)))
        }
        return result
    }

    @Test fun immutableSdkShowsErrorInsteadOfLoadingAds() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val view = ProtectedWebViewFactory.create(activity)
                activity.showWindow(view)
                view.loadDataWithBaseURL(
                    MainActivity.HOME,
                    """
                    <script>setTimeout(function(){
                      window.YaGames = {init:function(){return Promise.resolve({adv:Object.freeze({
                        showFullscreenAdv:function(){}
                      })});}};
                      YaGames.init().catch(function(){});
                    }, 20);</script>
                    """.trimIndent(),
                    "text/html",
                    "utf-8",
                    null
                )
            }
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
            var blocked = false
            while (System.nanoTime() < deadline) {
                scenario.onActivity { activity ->
                    blocked =
                        allViews(activity.findViewById(android.R.id.content)).none { it is WebView }
                }
                if (blocked) break
                Thread.sleep(100)
            }
            assertTrue(
                "Unsupported SDK removes the game surface instead of returning unsafe methods",
                blocked
            )
        }
    }

    @Test fun rendererRestartDoesNotReplayReward() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var game: WebView
            scenario.onActivity { activity ->
                game = ProtectedWebViewFactory.create(activity)
                activity.showWindow(game)
                game.loadDataWithBaseURL(
                    MainActivity.HOME,
                    """
                    <script>
                    window.fixtureRewards = 0;
                    window.YaGames = {init:function(){return Promise.resolve({adv:{
                      showRewardedVideo:function(){}
                    }});}};
                    YaGames.init().then(function(sdk){sdk.adv.showRewardedVideo({callbacks:{
                      onRewarded:function(){window.fixtureRewards++;}
                    }});});
                    </script>
                    """.trimIndent(),
                    "text/html",
                    "utf-8",
                    null
                )
            }
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
            var rewarded = "0"
            while (System.nanoTime() < deadline) {
                rewarded = evaluate(game, "window.fixtureRewards || 0")
                if (rewarded == "1") break
                Thread.sleep(100)
            }
            assertEquals("Initial reward is completed once", "1", rewarded)
            instrumentation.runOnMainSync { game.loadUrl("chrome://crash") }
            val crashDeadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
            var removed = false
            while (System.nanoTime() < crashDeadline) {
                scenario.onActivity { activity ->
                    removed =
                        allViews(activity.findViewById(android.R.id.content)).none { it is WebView }
                }
                if (removed) break
                Thread.sleep(100)
            }
            assertTrue("Crashed views are removed and a recovery action is shown", removed)
            scenario.onActivity { activity ->
                allViews(
                    activity.findViewById(android.R.id.content)
                ).filterIsInstance<android.widget.Button>().last().performClick()
            }
            lateinit var restored: WebView
            scenario.onActivity { activity ->
                restored =
                    allViews(
                        activity.findViewById(android.R.id.content)
                    ).filterIsInstance<WebView>().single()
            }
            val restoreDeadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
            var restoredURL: String? = null
            while (System.nanoTime() < restoreDeadline) {
                scenario.onActivity { restoredURL = restored.url }
                if (restoredURL?.startsWith("https://") == true) break
                Thread.sleep(100)
            }
            assertTrue(
                "Retry returns to the saved HTTPS page, not the internal crash URL",
                restoredURL?.startsWith("https://") == true
            )
            assertEquals(
                "Old reward request is not inserted in the new document",
                "0",
                evaluate(restored, "window.fixtureRewards || 0")
            )
        }
    }
}
