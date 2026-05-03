package games.yandex.wrap.webview

import android.graphics.Bitmap
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import java.io.ByteArrayInputStream

class AdBlockingClient(
    private val blockList: BlockList,
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
    }

    private companion object {
        val EMPTY_BYTES = byteArrayOf()
    }
}
