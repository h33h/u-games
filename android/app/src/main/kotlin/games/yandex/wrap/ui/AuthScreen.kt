package games.yandex.wrap.ui

import android.annotation.SuppressLint
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import games.yandex.wrap.config.AppConfig
import games.yandex.wrap.diagnostics.LogStore
import games.yandex.wrap.diagnostics.UgamesLogJsBridge
import games.yandex.wrap.webview.installLogBridgeShim
import kotlinx.coroutines.delay

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun AuthScreen(config: AppConfig, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    val webViewRef = remember { mutableStateOf<WebView?>(null) }
    val dismissed = remember { mutableStateOf(false) }

    val passportHost = remember { config.yandex.passportOrigin().host }
    val authUrl = remember { config.yandex.authUrl().toString() }
    val gamesRootUrl = remember { config.yandex.gamesHome().toString() }

    // Cookie-driven auth completion. Yandex's passport flow keeps changing
    // (/pwl-yandex/auth/add, /webauthn-reg, /finish?, /profile/setup,
    // /auth/welcome, …) — chasing dead-end URL patterns is fragile. Once
    // Session_id on yandex.ru is enough to treat the WebView login as complete.
    // URL patterns in Passport change often, so the watcher stays cookie-driven.
    LaunchedEffect(Unit) {
        LogStore.log(
            "auth",
            "AuthView opened: passportHost=$passportHost retpath=${config.yandex.gamesHome()} gamesHost=${config.yandex.origin().host}",
        )
        val cm = CookieManager.getInstance()
        var ticks = 0
        while (!dismissed.value) {
            delay(400)
            ticks++
            val raw = cm.getCookie(config.yandex.origin().toString()).orEmpty()
            val sessionPresent = raw.split(';').any { it.trim().startsWith("Session_id=") }
            if (ticks % 5 == 0) {
                LogStore.log(
                    "cookie",
                    "tick=$ticks waiting for Session_id@${config.yandex.origin().host}; cookieLen=${raw.length}",
                )
            }
            if (!sessionPresent) continue

            val wv = webViewRef.value ?: continue
            val current = wv.url.orEmpty()
            LogStore.log("auth", "Session_id detected after ${ticks * 400}ms; current=$current")
            if (!config.yandex.isGamesUrl(current)) {
                LogStore.log("auth", "force-loading $gamesRootUrl")
                wv.post { wv.loadUrl(gamesRootUrl) }
            }
            // Grace window lets WebView flush the final Passport cookies.
            delay(2500)
            if (dismissed.value) return@LaunchedEffect
            dismissed.value = true
            val finalUrl = wv.url.orEmpty()
            val yandexRaw = cm.getCookie(config.yandex.origin().toString()).orEmpty()
            val yandexSessions = if (yandexRaw.contains("Session_id=")) 1 else 0
            LogStore.log(
                "auth",
                "post-grace dismiss; finalUrl=$finalUrl yandexSessions=$yandexSessions",
            )
            onClose()
            return@LaunchedEffect
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .windowInsetsPadding(WindowInsets.statusBars),
    ) {
        AndroidView(
            modifier = Modifier.fillMaxSize().padding(top = 56.dp),
            factory = { ctx ->
                WebView(ctx).apply {
                    webViewRef.value = this
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    )
                    settings.apply {
                        javaScriptEnabled = true
                        domStorageEnabled = true
                        databaseEnabled = true
                        cacheMode = WebSettings.LOAD_DEFAULT
                        userAgentString = config.http.userAgent
                    }
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)

                    // Log bridge — same as GameWebView, so passport-side
                    // scripts can also post diagnostic events. Useful to
                    // confirm we land on the page we expect (PWL flow,
                    // /finish?, etc.).
                    addJavascriptInterface(UgamesLogJsBridge(), "ugamesLog")
                    installLogBridgeShim(this, config)

                    webViewClient = object : WebViewClient() {
                        private fun checkUrl(view: WebView?, url: String?) {
                            if (dismissed.value || url == null) return
                            CookieManager.getInstance().flush()
                            // Yandex's "Make sign-in easier" webauthn step is a
                            // dead end inside our WebView (no biometric prompt),
                            // so jump straight to our retpath.
                            if (url.contains("/webauthn-reg") || url.contains("/finish?")) {
                                LogStore.log("auth", "skip dead-end $url")
                                view?.loadUrl(gamesRootUrl)
                                return
                            }
                            // No URL-based dismiss here. The watcher waits for
                            // Session_id and gives WebView a short grace window
                            // to complete cookie writes.
                        }

                        override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                            super.onPageStarted(view, url, favicon)
                            LogStore.log("nav", "auth start ${url ?: "?"}")
                            checkUrl(view, url)
                        }

                        override fun onPageFinished(view: WebView?, url: String?) {
                            super.onPageFinished(view, url)
                            LogStore.log("nav", "auth finish ${url ?: "?"}")
                            checkUrl(view, url)
                        }

                        override fun doUpdateVisitedHistory(view: WebView?, url: String?, isReload: Boolean) {
                            super.doUpdateVisitedHistory(view, url, isReload)
                            checkUrl(view, url)
                        }
                    }
                    loadUrl(authUrl)
                }
            }
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color.Black)
                .padding(horizontal = 4.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onClose) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "Back",
                    tint = Color.White,
                    modifier = Modifier.size(28.dp),
                )
            }
            Text(
                text = "Sign in to Yandex",
                color = Color.White,
                fontSize = 18.sp,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}
