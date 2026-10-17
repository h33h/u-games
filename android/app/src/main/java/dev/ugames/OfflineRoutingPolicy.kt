package dev.ugames

object OfflineRoutingPolicy {
    const val HOME = "https://yandex.ru/games/"
    fun startupUrl(internetAvailable: Boolean, restoredUrl: String) =
        if (internetAvailable) restoredUrl else HOME
    fun cachedGame(
        url: String,
        internetAvailable: Boolean,
        games: List<SavedOfflineGame>
    ): SavedOfflineGame? {
        if (internetAvailable) return null
        val key = OfflineResourcePolicy.normalize(url) ?: return null
        return games.firstOrNull { OfflineResourcePolicy.normalize(it.entryUrl) == key }
    }
}
