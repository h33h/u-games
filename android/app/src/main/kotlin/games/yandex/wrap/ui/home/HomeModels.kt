package games.yandex.wrap.ui.home

import games.yandex.wrap.catalog.Game

data class SpotlightBlock(val title: String, val games: List<Game>)

data class GenreRow(val title: String, val categoryName: String?, val games: List<Game>)
