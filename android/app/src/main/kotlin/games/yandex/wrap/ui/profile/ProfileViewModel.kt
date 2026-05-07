package games.yandex.wrap.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import games.yandex.wrap.catalog.CatalogRepository
import games.yandex.wrap.catalog.UserProfile
import games.yandex.wrap.diagnostics.LogStore
import java.util.Locale
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Backs ProfileScreen. Mirrors the resilient profile-fetch pattern from
 * the legacy CatalogViewModel — wait for Session_id on the locale-preferred
 * Yandex domain, then retry the SSR fetch with growing back-off so the
 * UI eventually reflects the authenticated session even if the WebView's
 * cookie flush is still in flight.
 */
class ProfileViewModel(private val repository: CatalogRepository) : ViewModel() {

    private val _profile = MutableStateFlow(UserProfile(false, "", "", "", false))
    val profile: StateFlow<UserProfile> = _profile.asStateFlow()

    init { refresh() }

    fun refresh(attempts: Int = 4) {
        viewModelScope.launch {
            LogStore.log("profile", "ProfileViewModel.refresh begin")
            val waited = waitForSessionCookie(timeoutMs = 3000)
            LogStore.log("profile", "Session_id wait: $waited")
            val delaysMs = longArrayOf(0, 350, 800, 1600)
            for (i in 0 until attempts) {
                val d = delaysMs[i.coerceAtMost(delaysMs.size - 1)]
                if (d > 0) delay(d)
                val p = runCatching { repository.userProfile() }.getOrNull()
                LogStore.log(
                    "profile",
                    "attempt#${i + 1} -> isAuth=${p?.isAuthorized} login=${p?.login.orEmpty()}",
                )
                if (p != null && p.isAuthorized) {
                    _profile.value = p
                    return@launch
                }
                if (i == attempts - 1 && p != null) _profile.value = p
            }
            LogStore.log("profile", "ProfileViewModel.refresh end (still anonymous)")
        }
    }

    fun signOut(onDone: () -> Unit = {}) {
        viewModelScope.launch {
            runCatching { repository.clearSession() }
            _profile.value = UserProfile(false, "", "", "", false)
            onDone()
        }
    }

    private suspend fun waitForSessionCookie(timeoutMs: Long): String {
        val cm = android.webkit.CookieManager.getInstance()
        val preferredHost =
            if (Locale.getDefault().language.lowercase().startsWith("ru")) "yandex.ru" else "yandex.com"
        val deadline = System.currentTimeMillis() + timeoutMs
        var ticks = 0
        while (System.currentTimeMillis() < deadline) {
            val raw = cm.getCookie("https://$preferredHost").orEmpty()
            if (raw.contains("Session_id=")) {
                return "found@$preferredHost after ${ticks * 150}ms"
            }
            delay(150)
            ticks++
        }
        return "TIMEOUT@$preferredHost after ${timeoutMs}ms"
    }
}
