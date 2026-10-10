package dev.ugames

import android.annotation.SuppressLint
import android.app.Activity
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Message
import android.view.View
import android.webkit.*
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.json.JSONObject
import java.io.ByteArrayInputStream

object ProtectedWebViewFactory {
    @SuppressLint("SetJavaScriptEnabled")
    fun create(activity: Activity, supportsDocumentStart: Boolean = WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)): WebView {
        if (!supportsDocumentStart) throw UnsupportedOperationException("Document-start injection is unavailable")
        val script = activity.assets.open("ugames/ad-adapter.js").bufferedReader().use { it.readText() }
        val rules = JSONObject(activity.assets.open("ugames/ad-rules.json").bufferedReader().use { it.readText() })
        val filter = AdResourceFilter(
            rules.getJSONArray("blockedHosts").let { list -> (0 until list.length()).map(list::getString) },
            rules.getJSONArray("blockedUrlPatterns").let { list -> (0 until list.length()).map(list::getString) }
        )
        WebView.setWebContentsDebuggingEnabled(activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0)
        return WebView(activity).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.setSupportMultipleWindows(true)
            settings.javaScriptCanOpenWindowsAutomatically = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            addJavascriptInterface(object {
                @JavascriptInterface
                fun unsupported() {
                    post {
                        stopLoading()
                        (activity as? MainActivity)?.showError("Эта игра пока не работает без рекламы. Выбери другую в каталоге.")
                    }
                }
            }, "__UGamesProtection")
            CookieManager.getInstance().setAcceptCookie(true)
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
            WebViewCompat.addDocumentStartJavaScript(this, script, setOf("*"))
            webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                    return if (filter.shouldBlock(request.url.toString())) {
                        WebResourceResponse("text/plain", "utf-8", 403, "Blocked advertisement", emptyMap(), ByteArrayInputStream(ByteArray(0)))
                    } else null
                }
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val scheme = request.url.scheme
                    if (scheme == "https" || scheme == "http" || scheme == "about") return false
                    (activity as? MainActivity)?.showError("Эту ссылку нельзя открыть внутри приложения.")
                    return true
                }
                override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                    (activity as? MainActivity)?.setLoading(view, true)
                }
                override fun onPageFinished(view: WebView, url: String?) {
                    CookieManager.getInstance().flush()
                    (activity as? MainActivity)?.setLoading(view, false)
                }
                override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                    if (request.isForMainFrame) (activity as? MainActivity)?.showError("Не удалось открыть страницу. Проверь подключение и попробуй ещё раз.")
                }
                override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                    if (request.isForMainFrame) (activity as? MainActivity)?.showError("Сервис не открыл страницу. Попробуй ещё раз.")
                }
                override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                    (activity as? MainActivity)?.rendererGone(view)
                    return true
                }
            }
            webChromeClient = object : WebChromeClient() {
                override fun onCreateWindow(view: WebView, isDialog: Boolean, isUserGesture: Boolean, resultMsg: Message): Boolean {
                    val owner = activity as? MainActivity ?: return false
                    val child = create(activity)
                    owner.showWindow(child)
                    (resultMsg.obj as WebView.WebViewTransport).webView = child
                    resultMsg.sendToTarget()
                    return true
                }
                override fun onCloseWindow(window: WebView) { (activity as? MainActivity)?.closeWindow(window) }
                override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                    (activity as? MainActivity)?.showFullscreen(view, callback)
                }
                override fun onHideCustomView() { (activity as? MainActivity)?.hideFullscreen() }
            }
        }
    }
}
