package games.yandex.wrap.catalog

data class FeedPage(
    val games: List<Game>,
    val nextPageId: String?,
    val hasNext: Boolean,
)

data class UserProfile(
    val isAuthorized: Boolean,
    val displayName: String,
    val login: String,
    val avatarUrl: String,
    val hasYaPlus: Boolean,
)
