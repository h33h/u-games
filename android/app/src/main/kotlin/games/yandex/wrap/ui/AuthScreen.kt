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
import games.yandex.wrap.config.YandexHost
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

    val preferredHost = remember { config.yandex.preferredHost }
    val passportHost = remember { config.yandex.passportOrigin().host }
    val authUrl = remember { config.yandex.authUrl().toString() }
    val gamesRootUrl = remember { config.yandex.gamesHome().toString() }

    // Cookie-driven auth completion. Yandex's passport flow keeps changing
    // (/pwl-yandex/auth/add, /webauthn-reg, /finish?, /profile/setup,
    // /auth/welcome, …) — chasing dead-end URL patterns is fragile. Once
    // Session_id lands on the PREFERRED domain (yandex.ru for Russian users,
    // yandex.com otherwise), the user is authenticated regardless of which
    // passport screen WebView happens to land on. We force-load /games/ so
    // navigation completes onto our retpath, then give WebView a 2.5s grace
    // to absorb the .com→.ru SSO redirect chain that establishes the
    // .yandex.ru session — without this grace the catalog fetch would still
    // be anonymous on Russian-locale devices.
    LaunchedEffect(Unit) {
        LogStore.log(
            "auth",
            "AuthView opened: passportHost=$passportHost retpath=${config.yandex.gamesHome()} gamesHost=${preferredHost.host}",
        )
        val cm = CookieManager.getInstance()
        var ticks = 0
        while (!dismissed.value) {
            delay(400)
            ticks++
            val raw = cm.getCookie(config.yandex.origin(preferredHost).toString()).orEmpty()
            val sessionPresent = raw.split(';').any { it.trim().startsWith("Session_id=") }
            if (ticks % 5 == 0) {
                LogStore.log(
                    "cookie",
                    "tick=$ticks waiting for Session_id@${preferredHost.host}; cookieLen=${raw.length}",
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
            // Grace window — the .com→.ru SSO chain takes ~1-2s on a real
            // device. Dismissing on first sight of Session_id leaves the
            // .yandex.ru session never established and the next /games/
            // fetch comes back anonymous.
            delay(2500)
            if (dismissed.value) return@LaunchedEffect
            dismissed.value = true
            val finalUrl = wv.url.orEmpty()
            val comRaw = cm.getCookie(config.yandex.origin(YandexHost.Com).toString()).orEmpty()
            val ruRaw = cm.getCookie(config.yandex.origin(YandexHost.Ru).toString()).orEmpty()
            val comSessions = if (comRaw.contains("Session_id=")) 1 else 0
            val ruSessions = if (ruRaw.contains("Session_id=")) 1 else 0
            LogStore.log(
                "auth",
                "post-grace dismiss; finalUrl=$finalUrl comSessions=$comSessions ruSessions=$ruSessions",
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
                            // Session_id on the preferred domain and gives
                            // WebView a 2.5s grace to complete the .com→.ru
                            // SSO chain — that's what gets the .yandex.ru
                            // session cookies set. Dismissing on first sight
                            // of /games/ short-circuits that and leaves auth
                            // half-finished.
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
