package games.yandex.wrap.catalog

import games.yandex.wrap.catalog.models.UserProfile

class ProfileRepository(
    private val api: CatalogApi,
    private val sessionStore: YandexSessionStore,
) {
    suspend fun userProfile(): UserProfile? = api.userProfile()

    suspend fun userProfileWithRetry(attempts: Int = 4): UserProfile? {
        sessionStore.sessionCookieHeader(timeoutMs = 3000)
        val delaysMs = longArrayOf(0, 350, 800, 1600)
        var last: UserProfile? = null
        for (i in 0 until attempts) {
            val delayMs = delaysMs[i.coerceAtMost(delaysMs.size - 1)]
            if (delayMs > 0) kotlinx.coroutines.delay(delayMs)
            val profile = runCatching { api.userProfile() }.getOrNull() ?: continue
            last = profile
            if (profile.isAuthorized) return profile
        }
        return last
    }

    suspend fun clearSession() {
        sessionStore.clearSession()
    }
}
