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
    /** Bare `prefix-url` from the cover entry — ends with `/`, no size
     *  suffix appended. Lets the Detail screen ask for a high-res variant
     *  (e.g. `pjpg1280x720`) without duplicating the URL string. */
    val coverPrefixUrl: String? = null,
) {
    val playUrl: String get() = "https://yandex.com/games/app/$appId"

    /** Compose a sized URL from [coverPrefixUrl]; falls back to the
     *  pre-baked thumbnail when the prefix isn't available (e.g. when a
     *  Game came from the favorites table). Yandex's avatars storage only
     *  serves the size suffixes that have been pre-rendered, so callers
     *  must stick to known-good values: `pjpg1280x720`, `pjpg500x280`,
     *  `pjpg256x256`, `pjpg250x140`, `orig`. */
    fun coverUrl(size: String): String =
        coverPrefixUrl?.let { it + size } ?: coverUrl
}
