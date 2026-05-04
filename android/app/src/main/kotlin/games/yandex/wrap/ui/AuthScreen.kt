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
import kotlinx.coroutines.delay

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun AuthScreen(onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    val webViewRef = remember { mutableStateOf<WebView?>(null) }

    // Cookie-driven auth completion. Yandex's passport flow keeps changing:
    // /pwl-yandex/auth/add (passwordless login), /webauthn-reg, /finish?,
    // /profile/setup, /auth/welcome, etc. — chasing each dead-end URL
    // pattern is fragile. Once the Session_id cookie is set on .yandex.com,
    // the user is authenticated regardless of which passport screen the
    // WebView happens to land on. Force-load /games/ so the existing
    // url.startsWith("https://yandex.com/games/") branch dismisses the
    // auth screen and triggers refreshProfile().
    LaunchedEffect(Unit) {
        val cm = android.webkit.CookieManager.getInstance()
        var redirected = false
        while (!redirected) {
            delay(400)
            val raw = cm.getCookie("https://yandex.com").orEmpty()
            if (raw.contains("Session_id=")) {
                redirected = true
                webViewRef.value?.let { wv ->
                    val current = wv.url ?: ""
                    if (!current.startsWith("https://yandex.com/games/") &&
                        !current.startsWith("https://yandex.ru/games/")) {
                        wv.post { wv.loadUrl("https://yandex.com/games/") }
                    }
                }
            }
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .windowInsetsPadding(WindowInsets.statusBars)
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
                    webViewClient = object : WebViewClient() {
                        private var dismissed = false

                        private fun checkUrl(view: WebView?, url: String?) {
                            if (dismissed || url == null) return
                            CookieManager.getInstance().flush()
                            // Yandex's "Make sign-in easier" webauthn step is a
                            // dead end inside our WebView (no biometric prompt),
                            // so jump straight to the retpath that already has
                            // valid Session_id cookies set.
                            if (url.contains("/webauthn-reg") || url.contains("/finish?")) {
                                view?.loadUrl("https://yandex.com/games/")
                                return
                            }
                            val isGames = url.startsWith("https://yandex.com/games/")
                                    || url.startsWith("https://yandex.ru/games/")
                            if (isGames) {
                                dismissed = true
                                onClose()
                            }
                        }

                        override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                            super.onPageStarted(view, url, favicon)
                            checkUrl(view, url)
                        }

                        override fun onPageFinished(view: WebView?, url: String?) {
                            super.onPageFinished(view, url)
                            checkUrl(view, url)
                        }

                        override fun doUpdateVisitedHistory(view: WebView?, url: String?, isReload: Boolean) {
                            super.doUpdateVisitedHistory(view, url, isReload)
                            checkUrl(view, url)
                        }
                    }
                    loadUrl("https://passport.yandex.com/auth?retpath=https%3A%2F%2Fyandex.com%2Fgames%2F")
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
