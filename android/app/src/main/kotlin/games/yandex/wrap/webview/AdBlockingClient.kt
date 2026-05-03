package games.yandex.wrap.webview

import android.graphics.Bitmap
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import java.io.ByteArrayInputStream

/**
 * Combines URL block-list (layer 3) and a fallback JS+CSS injector for the main
 * frame: documentStart-script registration is the primary path, but on devices
 * where it is unreliable we additionally re-inject in onPageStarted /
 * onPageCommitVisible to guarantee that the catalog chrome is hidden before
 * the user sees any flash of unstyled content.
 */
class AdBlockingClient(
    private val blockList: BlockList,
    private val scripts: InjectedScripts,
) : WebViewClient() {

    override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
        val url = request?.url?.toString() ?: return null
        if (blockList.isBlocked(url)) {
            return WebResourceResponse(
                "text/plain",
                "utf-8",
                ByteArrayInputStream(EMPTY_BYTES),
            )
        }
        return null
    }

    override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
        super.onPageStarted(view, url, favicon)
        injectIfYandex(view, url)
    }

    override fun onPageCommitVisible(view: WebView?, url: String?) {
        super.onPageCommitVisible(view, url)
        injectIfYandex(view, url)
    }

    private fun injectIfYandex(view: WebView?, url: String?) {
        if (view == null || url == null) return
        when {
            url.startsWith("https://yandex.com/games") || url.startsWith("https://yandex.ru/games") -> {
                view.evaluateJavascript(scripts.mainFrameScript, null)
            }
            url.contains(".games.s3.yandex.net/") -> {
                view.evaluateJavascript(scripts.sdkStub, null)
            }
        }
    }

    private companion object {
        val EMPTY_BYTES = byteArrayOf()
    }
}

@Suppress("unused")
fun installDocumentStartScripts(webView: WebView, scripts: InjectedScripts) {
    if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) return
    WebViewCompat.addDocumentStartJavaScript(
        webView,
        scripts.mainFrameScript,
        setOf("https://yandex.com", "https://yandex.ru"),
    )
    WebViewCompat.addDocumentStartJavaScript(
        webView,
        scripts.sdkStub,
        setOf("https://*.games.s3.yandex.net"),
    )
}
