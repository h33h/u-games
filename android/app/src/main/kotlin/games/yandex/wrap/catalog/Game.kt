package games.yandex.wrap.catalog

data class Game(
    val appId: Long,
    val title: String,
    val rating: Float,
    val ratingCount: Int,
    val coverUrl: String,
    val iconUrl: String,
    val categories: List<String>,
    val developer: String,
    /** Hex like "#41B4F6". Used for halo glow + image placeholder. */
    val mainColor: String? = null,
    /** Hex of the icon's mainColor. Used for square cards (recently row). */
    val iconMainColor: String? = null,
    /** Direct mp4 URL from media.videos[0].mp4StreamUrl, for Hero autoplay. */
    val videoUrl: String? = null,
) {
    val playUrl: String get() = "https://yandex.com/games/app/$appId"
}
