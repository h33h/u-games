package games.yandex.wrap.network

import games.yandex.wrap.network.dtos.FeedResponseDto

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
    override val path = "/games/api/catalogue/v2/search/"
    override val serializer = FeedResponseDto.serializer()
    override val query: Map<String, String>
        get() = query(
            "query" to queryValue,
            "platform" to "android_other",
            "games_count" to gamesPerPage.toString(),
            "page_id" to pageId,
        )
}
