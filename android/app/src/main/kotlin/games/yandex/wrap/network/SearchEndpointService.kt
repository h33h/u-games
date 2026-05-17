package games.yandex.wrap.network

import games.yandex.wrap.network.dtos.FeedResponseDto
import games.yandex.wrap.utils.Constants

class SearchEndpointService(
    private val networkService: NetworkService? = null,
) {
    suspend fun search(
        query: String,
        pageId: String? = null,
        gamesPerPage: Int = 24,
    ): FeedResponseDto = requireNetworkService().execute(
        SearchRequest(queryValue = query, pageId = pageId, gamesPerPage = gamesPerPage)
    )

    private fun requireNetworkService(): NetworkService =
        requireNotNull(networkService) { "NetworkService is required to execute search requests." }
}

data class SearchRequest(
    private val queryValue: String,
    private val pageId: String?,
    private val gamesPerPage: Int,
) : Request<FeedResponseDto> {
    override val path = "/games/api/catalogue/v3/search/"
    override val serializer = FeedResponseDto.serializer()
    override val query: Map<String, String>
        get() {
            val screenSize = Constants.UI.screenSize
            return query(
                "query" to queryValue,
                "platform" to "android_other",
                "with_promos" to "true",
                "games_count" to gamesPerPage.toString(),
                "page_id" to pageId,
                "client_width" to screenSize.width.toString(),
                "client_height" to screenSize.height.toString(),
                "found_width" to screenSize.width.toString(),
            )
        }
}
