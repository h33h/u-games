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
import androidx.compose.material.icons.filled.ArrowBack
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
import games.yandex.wrap.diagnostics.LogStore
import games.yandex.wrap.diagnostics.UgamesLogJsBridge
import games.yandex.wrap.webview.installLogBridgeShim
import kotlinx.coroutines.delay
import java.util.Locale

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun AuthScreen(onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    val webViewRef = remember { mutableStateOf<WebView?>(null) }
    val dismissed = remember { mutableStateOf(false) }

    val preferredHost = remember { preferredYandexHost() }
    val passportHost = remember { passportHostFor(preferredHost) }
    val retpathEncoded = remember { "https%3A%2F%2F$preferredHost%2Fgames%2F" }
    val authUrl = remember { "https://$passportHost/auth?retpath=$retpathEncoded" }
    val gamesRootUrl = remember { "https://$preferredHost/games/" }

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
            "AuthView opened: passportHost=$passportHost retpath=$retpathEncoded gamesHost=$preferredHost",
        )
        val cm = CookieManager.getInstance()
        var ticks = 0
        while (!dismissed.value) {
            delay(400)
            ticks++
            val raw = cm.getCookie("https://$preferredHost").orEmpty()
            val sessionPresent = raw.split(';').any { it.trim().startsWith("Session_id=") }
            if (ticks % 5 == 0) {
                LogStore.log(
                    "cookie",
                    "tick=$ticks waiting for Session_id@$preferredHost; cookieLen=${raw.length}",
                )
            }
            if (!sessionPresent) continue

            val wv = webViewRef.value ?: continue
            val current = wv.url.orEmpty()
            LogStore.log("auth", "Session_id detected after ${ticks * 400}ms; current=$current")
            if (!current.startsWith("https://yandex.com/games/") &&
                !current.startsWith("https://yandex.ru/games/")
            ) {
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
            val comRaw = cm.getCookie("https://yandex.com").orEmpty()
            val ruRaw = cm.getCookie("https://yandex.ru").orEmpty()
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
                        userAgentString = userAgentString.replace("; wv)", ")")
                    }
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)

                    // Log bridge — same as GameWebView, so passport-side
                    // scripts can also post diagnostic events. Useful to
                    // confirm we land on the page we expect (PWL flow,
                    // /finish?, etc.).
                    addJavascriptInterface(UgamesLogJsBridge(), "ugamesLog")
                    installLogBridgeShim(this)

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
                    Icons.Default.ArrowBack,
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

/**
 * Use yandex.ru/passport.yandex.ru for Russian-locale devices. Yandex runs
 * separate session realms per TLD: passport.yandex.com only ever issues
 * Session_id for `.yandex.com`, and yandex.ru's SSR rejects that session when
 * serving userData. For Russian users the auth must go through
 * passport.yandex.ru directly so Session_id lands on `.yandex.ru`.
 */
internal fun preferredYandexHost(): String =
    if (Locale.getDefault().language.lowercase().startsWith("ru")) "yandex.ru" else "yandex.com"

internal fun passportHostFor(yandexHost: String): String =
    if (yandexHost == "yandex.ru") "passport.yandex.ru" else "passport.yandex.com"
