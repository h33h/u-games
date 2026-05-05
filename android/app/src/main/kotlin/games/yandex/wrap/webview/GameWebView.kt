package games.yandex.wrap.webview

import android.annotation.SuppressLint
import android.graphics.Color
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import games.yandex.wrap.diagnostics.UgamesLogJsBridge

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun GameWebView(
    url: String,
    scripts: InjectedScripts,
    blockList: BlockList,
    modifier: Modifier = Modifier,
) {
    val savedScripts = remember { scripts }
    val savedBlockList = remember { blockList }

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            val container = FrameLayout(ctx).apply {
                setBackgroundColor(Color.BLACK)
            }
            val webView = WebView(ctx)
            webView.layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            // Black background eliminates the white flash before our PWA-CSS
            // hides the catalog chrome.
            webView.setBackgroundColor(Color.BLACK)
            webView.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                databaseEnabled = true
                mediaPlaybackRequiresUserGesture = false
                loadWithOverviewMode = true
                useWideViewPort = true
                javaScriptCanOpenWindowsAutomatically = true
                setSupportMultipleWindows(true)
                cacheMode = WebSettings.LOAD_DEFAULT
                userAgentString = userAgentString.replace("; wv)", ")")
            }

            CookieManager.getInstance().setAcceptCookie(true)
            CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)

            // Bridge `window.__yga_log(tag, msg)` from inject scripts to native
            // LogStore + OrientationStore. Mirrors iOS WKScriptMessageHandler
            // named "ugamesLog" in GameWebView.swift. Must be installed BEFORE
            // documentStart scripts, otherwise the SDK stub's first orient
            // dispatch races registration and is lost.
            webView.addJavascriptInterface(UgamesLogJsBridge(), "ugamesLog")

            webView.webViewClient = AdBlockingClient(savedBlockList, savedScripts)
            webView.webChromeClient = PopupHandler(ctx, container)

            installLogBridgeShim(webView)
            installDocumentStartScripts(webView, savedScripts)

            WebView.setWebContentsDebuggingEnabled(true)
            webView.loadUrl(url)
            container.addView(webView)
            container
        },
        update = { container ->
            val webView = container.getChildAt(0) as? WebView
            if (webView != null && webView.url != url) {
                webView.loadUrl(url)
            }
        },
        onRelease = { container ->
            val webView = container.getChildAt(0) as? WebView
            webView?.destroy()
        }
    )

    DisposableEffect(Unit) {
        onDispose { CookieManager.getInstance().flush() }
    }
}
