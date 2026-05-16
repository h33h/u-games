package games.yandex.wrap.ui.detail

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import games.yandex.wrap.catalog.CatalogRepository
import games.yandex.wrap.catalog.FavoritesRepository
import games.yandex.wrap.catalog.Game
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Drives `GameDetailScreen`. Loads "More like this" via the
 * `similar_games` endpoint and mirrors favorites state from the
 * repository so the heart icon stays in sync with Home/Browse.
 */
class GameDetailViewModel(
    private val catalogRepository: CatalogRepository,
    private val favoritesRepository: FavoritesRepository,
    initialGame: Game,
) : ViewModel() {

    private val _state = MutableStateFlow(GameDetailUiState(game = initialGame))
    val state: StateFlow<GameDetailUiState> = _state.asStateFlow()

    init {
        // Seed favorite flag + the full set so similar-row tiles show the
        // correct heart icon for any game the user already saved.
        viewModelScope.launch {
            favoritesRepository.favoriteIds().collect { ids ->
                _state.update {
                    it.copy(
                        isFavorite = ids.contains(it.game.appId),
                        favoriteIds = ids,
                    )
                }
            }
        }
        loadSimilar()
        loadDetail()
    }

    fun loadDetail() {
        if (_state.value.isLoadingDetail) return
        _state.update { it.copy(isLoadingDetail = true) }
        viewModelScope.launch {
            val res = catalogRepository.appDetail(_state.value.game.appId)
            _state.update {
                it.copy(
                    isLoadingDetail = false,
                    detail = res.getOrNull() ?: it.detail,
                )
            }
        }
    }

    fun loadSimilar() {
        val current = _state.value
        if (current.isLoadingSimilar) return
        _state.update { it.copy(isLoadingSimilar = true, similarError = null) }
        viewModelScope.launch {
            val result = catalogRepository.similar(current.game.appId)
            result.fold(
                onSuccess = { games ->
                    _state.update {
                        it.copy(
                            isLoadingSimilar = false,
                            // Drop the same game if the server happens to
                            // include it in its own "similar" list.
                            similar = games.filter { g -> g.appId != it.game.appId },
                            similarError = null,
                        )
                    }
                },
                onFailure = { err ->
                    _state.update {
                        it.copy(
                            isLoadingSimilar = false,
                            similarError = err.message,
                        )
                    }
                },
            )
        }
    }

    fun toggleFavorite() {
        val game = _state.value.game
        viewModelScope.launch {
            runCatching { favoritesRepository.toggleFavorite(game) }
        }
    }
}
