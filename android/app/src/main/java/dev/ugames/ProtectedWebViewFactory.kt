package dev.ugames

import android.annotation.SuppressLint
import android.app.Activity
import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.os.Message
import android.view.View
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import java.io.ByteArrayInputStream
import org.json.JSONObject

object ProtectedWebViewFactory {
    val defaultBackground: Int = Color.rgb(23, 21, 32)

    @SuppressLint("SetJavaScriptEnabled")
    fun create(
        activity: Activity,
        supportsDocumentStart: Boolean = WebViewFeature.isFeatureSupported(
            WebViewFeature.DOCUMENT_START_SCRIPT
        ),
        isPopup: Boolean = false,
        offlineGame: SavedOfflineGame? = null
    ): WebView {
        if (!supportsDocumentStart ||
            !WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)
        ) {
            throw UnsupportedOperationException(
                "Document-start injection is unavailable"
            )
        }
        val script = activity.assets.open("ugames/ad-adapter.js").bufferedReader().use {
            it.readText()
        }
        val filter = resourceFilter(activity)
        val playback = offlineGame?.let { OfflineWebPlayback(it, filter) }
        OfflineWebPlayback.configureServiceWorkers(playback, filter)
        WebView.setWebContentsDebuggingEnabled(
            activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        )
        return WebView(activity).apply {
            setBackgroundColor(defaultBackground)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.setSupportMultipleWindows(true)
            settings.javaScriptCanOpenWindowsAutomatically = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            if (offlineGame != null) {
                settings.blockNetworkLoads = true
                settings.cacheMode = WebSettings.LOAD_NO_CACHE
                (activity as? MainActivity)?.registerOfflineWindow(this, offlineGame)
            }
            addJavascriptInterface(
                object {
                    @JavascriptInterface
                    fun offlinePreparationFailed() {
                        if (offlineGame != null) {
                            post {
                                (activity as? MainActivity)?.showError(
                                    "Не удалось подготовить сохранённую игру. Попробуй открыть её ещё раз."
                                )
                            }
                        }
                    }

                    @JavascriptInterface
                    fun unsupported() {
                        post {
                            stopLoading()
                            (activity as? MainActivity)?.showError(
                                "Эта игра пока не работает без рекламы. Выбери другую в каталоге."
                            )
                        }
                    }
                },
                "__UGamesProtection"
            )
            WebViewCompat.addWebMessageListener(this, "__UGamesAppearance", setOf("*")) {
                    view,
                    message,
                    _,
                    mainFrame,
                    _
                ->
                if (!mainFrame ||
                    message.type != WebMessageCompat.TYPE_STRING
                ) {
                    return@addWebMessageListener
                }
                val value = message.data
                if (value != null && value.matches(Regex("#[0-9a-fA-F]{6}"))) {
                    (activity as? MainActivity)?.setPageBackground(view, Color.parseColor(value))
                }
            }
            WebViewCompat.addWebMessageListener(
                this,
                "__UGamesOffline",
                setOf("https://*.games.yandex.net", "https://*.games.s3.yandex.net")
            ) {
                    view,
                    message,
                    sourceOrigin,
                    _,
                    _
                ->
                if (message.type == WebMessageCompat.TYPE_STRING) {
                    message.data?.let { data ->
                        (activity as? MainActivity)?.receiveOfflineReport(
                            view,
                            data,
                            sourceOrigin.toString()
                        )
                    }
                }
            }
            CookieManager.getInstance().setAcceptCookie(true)
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
            if (offlineGame != null) {
                WebViewCompat.addDocumentStartJavaScript(
                    this,
                    offlineGame.configurationScript() + requireNotNull(
                        playback
                    ).preparationScript(),
                    setOf(requireNotNull(OfflineResourcePolicy.origin(offlineGame.entryUrl)))
                )
            }
            WebViewCompat.addDocumentStartJavaScript(this, script, setOf("*"))
            webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(
                    view: WebView,
                    request: WebResourceRequest
                ): WebResourceResponse? = if (playback != null &&
                    request.url.scheme in setOf("data", "blob", "about")
                ) {
                    // Inline documents and game-generated blobs cannot make a network request.
                    null
                } else if (playback != null) {
                    playback.response(request)
                } else if (
                    filter.shouldBlock(request.url.toString()) ||
                    GameNavigationPolicy.blocksDocumentRequest(
                        request.url.toString(),
                        request.isForMainFrame,
                        request.requestHeaders
                    )
                ) {
                    WebResourceResponse(
                        "text/plain",
                        "utf-8",
                        403,
                        "Blocked destination",
                        emptyMap(),
                        ByteArrayInputStream(ByteArray(0))
                    )
                } else {
                    null
                }
                override fun shouldOverrideUrlLoading(
                    view: WebView,
                    request: WebResourceRequest
                ): Boolean {
                    if (playback != null) return !playback.allowsDocument(request.url.toString())
                    if (request.isForMainFrame) {
                        val blocked = !GameNavigationPolicy.allows(request.url.toString())
                        if (blocked && isPopup && (view.url == null || view.url == "about:blank")) {
                            view.post { (activity as? MainActivity)?.closeWindow(view) }
                        }
                        return blocked
                    }
                    val source = request.requestHeaders.entries.firstOrNull {
                        it.key.equals("Referer", ignoreCase = true)
                    }?.value
                    return !GameNavigationPolicy.allowsFrame(request.url.toString(), source)
                }
                override fun onPageStarted(
                    view: WebView,
                    url: String?,
                    favicon: android.graphics.Bitmap?
                ) {
                    (activity as? MainActivity)?.navigationStarted(view)
                    (activity as? MainActivity)?.setLoading(view, true)
                }
                override fun onPageFinished(view: WebView, url: String?) {
                    CookieManager.getInstance().flush()
                    (activity as? MainActivity)?.setLoading(view, false)
                }
                override fun onReceivedError(
                    view: WebView,
                    request: WebResourceRequest,
                    error: WebResourceError
                ) {
                    if (request.isForMainFrame) {
                        (activity as? MainActivity)?.showError(
                            if (offlineGame !=
                                null
                            ) {
                                "Не удалось открыть сохранённую игру. Сохрани её ещё раз из каталога."
                            } else {
                                "Не удалось открыть страницу. Проверь подключение или открой сохранённую игру."
                            }
                        )
                    }
                }
                override fun onReceivedHttpError(
                    view: WebView,
                    request: WebResourceRequest,
                    response: WebResourceResponse
                ) {
                    if (request.isForMainFrame) {
                        (activity as? MainActivity)?.showError(
                            "Сервис не открыл страницу. Попробуй ещё раз."
                        )
                    }
                }
                override fun onRenderProcessGone(
                    view: WebView,
                    detail: RenderProcessGoneDetail
                ): Boolean {
                    (activity as? MainActivity)?.rendererGone(view)
                    return true
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onCreateWindow(
                    view: WebView,
                    isDialog: Boolean,
                    isUserGesture: Boolean,
                    resultMsg: Message
                ): Boolean {
                    if (offlineGame != null) return false
                    val owner = activity as? MainActivity ?: return false
                    val child = create(activity, isPopup = true)
                    owner.showWindow(child)
                    (resultMsg.obj as WebView.WebViewTransport).webView = child
                    resultMsg.sendToTarget()
                    return true
                }
                override fun onCloseWindow(window: WebView) {
                    (activity as? MainActivity)?.closeWindow(window)
                }
                override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                    (activity as? MainActivity)?.showFullscreen(view, callback)
                }
                override fun onHideCustomView() {
                    (activity as? MainActivity)?.hideFullscreen()
                }
            }
        }
    }

    fun resourceFilter(activity: Activity): AdResourceFilter {
        val rules =
            JSONObject(
                activity.assets.open("ugames/ad-rules.json").bufferedReader().use {
                    it.readText()
                }
            )
        return AdResourceFilter(
            rules.getJSONArray("blockedHosts").let { list ->
                (0 until list.length()).map(list::getString)
            },
            rules.getJSONArray("blockedUrlPatterns").let { list ->
                (0 until list.length()).map(list::getString)
            }
        )
    }

    fun loadOfflineGame(view: WebView, game: SavedOfflineGame) {
        // Native document-start injection stops any old worker's cached document before scripts run.
        // It unregisters that worker, then loads the saved entry at its original secure origin.
        view.loadUrl(OfflineWebPlayback.bootstrapUrl(game))
    }
}
