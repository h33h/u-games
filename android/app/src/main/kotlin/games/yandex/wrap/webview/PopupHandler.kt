package games.yandex.wrap.webview

import android.content.Context
import android.os.Message
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import androidx.webkit.WebViewClientCompat

class PopupHandler(
    private val context: Context,
    private val container: ViewGroup,
) : WebChromeClient() {

    private var popup: WebView? = null

    override fun onCreateWindow(
        view: WebView?,
        isDialog: Boolean,
        isUserGesture: Boolean,
        resultMsg: Message?,
    ): Boolean {
        val popup = WebView(context).also { this.popup = it }
        popup.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        popup.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            javaScriptCanOpenWindowsAutomatically = true
            setSupportMultipleWindows(true)
            cacheMode = WebSettings.LOAD_DEFAULT
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(popup, true)
        popup.webViewClient = object : WebViewClientCompat() {}
        popup.webChromeClient = object : WebChromeClient() {
            override fun onCloseWindow(window: WebView?) {
                dismiss()
            }
        }
        container.addView(popup)
        val transport = resultMsg?.obj as? WebView.WebViewTransport ?: return false
        transport.webView = popup
        resultMsg.sendToTarget()
        return true
    }

    override fun onCloseWindow(window: WebView?) {
        dismiss()
    }

    fun dismiss() {
        popup?.let {
            container.removeView(it)
            it.destroy()
        }
        popup = null
    }
}
