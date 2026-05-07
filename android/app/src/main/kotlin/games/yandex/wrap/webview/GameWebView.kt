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
import androidx.compose.runtime.mutableStateOf
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
    paused: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val savedScripts = remember { scripts }
    val savedBlockList = remember { blockList }
    // Track the last applied paused state so update only flips onPause/
    // onResume when the flag actually changes. Calling onPause/pauseTimers
    // on every recomposition was harmless on the success path but the
    // wasted work made the WebView visibly stutter during scroll-driven
    // tab redraws (e.g. the rotate overlay flicking on for a frame).
    val lastPausedRef = remember { mutableStateOf<Boolean?>(null) }

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
            val webView = container.getChildAt(0) as? WebView ?: return@AndroidView
            if (webView.url != url) webView.loadUrl(url)
            // Pause/resume both the View and JS timers so games that locked an
            // orientation we can't satisfy aren't burning frames behind the
            // rotate overlay. resumeTimers is global on WebView prior to API
            // 28, so calling it on a single instance is enough.
            //
            // Only flip when paused changes — and skip the very first call
            // when paused is false, because the WebView starts running by
            // default and an unconditional resumeTimers() before loadUrl
            // finishes can race some game engines' boot sequence.
            val last = lastPausedRef.value
            if (last == null && !paused) {
                lastPausedRef.value = paused
            } else if (last != paused) {
                lastPausedRef.value = paused
                if (paused) {
                    webView.onPause()
                    webView.pauseTimers()
                } else {
                    webView.onResume()
                    webView.resumeTimers()
                }
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
