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
) {
    val playUrl: String get() = "https://yandex.com/games/app/$appId"
}
