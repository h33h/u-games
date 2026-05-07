# U-Games Redesign — Phase 2: Home / Browse / Favorites / Profile split

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Заменить единый `CatalogScreen` / `CatalogView` на 4 полноценных таба — `Home` (editorial: Hero + кураторские ряды + Spotlight), `Browse` (chips + grid + search), `Favorites` (grid + EmptyState), `Profile` (заменяет `ProfileSheet`) + `About`. Старый код Catalog* удаляется в конце фазы.

**Architecture:** Параллельно Android (Kotlin/Compose) + iOS (Swift/SwiftUI). Phase 1 уже даёт все building blocks (`TileGameCard`, `WideGameCard`, `SquareGameCard`, `HeroSection`, `StoryCard`, `GenreChipRow`, `Skeleton`, `EmptyState`, `ErrorState`, `FloatingTabBar`, theme tokens). Phase 2 — это новые экраны+VM-ы, новый блок-aware feed-парсер для Home, и переписывание `TabContainer` в реальную мульти-таб навигацию с независимыми push-стэками. Click по карточке всё ещё ведёт прямо в WebView (`GameScreen` / `GameView`) — `GameDetail` появится в Phase 3.

**Tech Stack:** существующий — Kotlin 2.0 / Compose Material3 / Ktor, Swift 5.9 / SwiftUI iOS 16+. Никаких новых зависимостей.

**Spec:** [`../specs/2026-05-05-ui-ux-redesign-design.md`](../specs/2026-05-05-ui-ux-redesign-design.md)

**Out of scope this phase:** GameDetail (Phase 3), in-game overlay (Phase 4), accessibility-проход (Phase 5), удаление мёртвого кода вне `CatalogScreen`/`CatalogView`/`ProfileSheet`.

---

## Conventions

- Каждая задача = 1 commit, ≤ 5-10 минут.
- Android verify: `cd android && ./gradlew :app:assembleDebug` зелёный (если задача меняет билд) + ручная проверка экрана через preview / запуск (если задача добавляет UI).
- iOS verify: `cd ios && xcodebuild -project UGames.xcodeproj -scheme UGames -sdk iphonesimulator -configuration Debug build` (или короче `xcodebuild -workspace …` если есть workspace) зелёный + preview / запуск.
- Цвет/типографика — только через `UGColors` / `UGType` (Android) и `UGColor` / `UGFont` (iOS). Ни одного хардкода `Color(0xFF…)` / `Color(red:…)` в новых файлах.
- Превью для каждого нового экрана.
- VM-state-классы — data class / struct, наружу `StateFlow` (Android) или `@Published` (iOS).
- Никакого нового форматирования старых файлов — только перечисленные изменения.

---

## File structure (после фазы)

### Android — новые

| Path | Что |
|---|---|
| `…/catalog/FeedBlock.kt` | data class `FeedBlock(type, size, title, items)` + `FeedWithBlocks` |
| `…/catalog/CatalogApi.kt` (extend) | `firstFeedPageWithBlocks()` + парсинг блоков и `siteNavigationLinks.categories` |
| `…/catalog/CatalogRepository.kt` (extend) | `firstFeedWithBlocks()` обёртка |
| `…/ui/home/HomeUiState.kt` | data class состояния Home |
| `…/ui/home/HomeViewModel.kt` | производит `HomeUiState` |
| `…/ui/home/HomeScreen.kt` | новый экран |
| `…/ui/browse/BrowseUiState.kt` | data class |
| `…/ui/browse/BrowseViewModel.kt` | feed pagination + chip-фильтр + поиск |
| `…/ui/browse/BrowseScreen.kt` | sticky topbar + GenreChipRow + grid |
| `…/ui/favorites/FavoritesScreen.kt` | grid + EmptyState (использует существующий `FavoritesDao`) |
| `…/ui/profile/ProfileViewModel.kt` | profile state + sign-out |
| `…/ui/profile/ProfileScreen.kt` | hero-секция + список settings |
| `…/ui/profile/AboutScreen.kt` | минимальный about |

### Android — изменяемые

| Path | Что |
|---|---|
| `…/ui/TabContainer.kt` | реальная 4-таб навигация: каждый таб владеет своим back-stack-ом (Home/Browse/Favorites/Profile + Game/Auth/Logs/About push-ом из таба). Bar скрывается, когда есть pushed-screen в активном табе. |
| `…/MainActivity.kt` | создаёт VM-ы для всех табов, передаёт в TabContainer; deep-link и Game push маршрутизируются как раньше |
| `…/ui/components/FloatingTabBar.kt` | (опционально, если потребуется badge для favorites count) — но Phase 2 не требует, оставляем как есть |

### Android — удаляемые

| Path | Когда |
|---|---|
| `…/ui/CatalogScreen.kt` | в конце фазы, после переезда `HorizontalGameRow`-логики (она уже не нужна — Home/Favorites используют `WideGameCard`/`SquareGameCard`) |
| `…/ui/CatalogViewModel.kt` | в конце фазы, логика разъехалась в Home/Browse/FavoritesViewModel |

### iOS — новые

| Path | Что |
|---|---|
| `…/Catalog/FeedBlock.swift` | `struct FeedBlock` + `FeedWithBlocks` |
| `…/Catalog/CatalogService.swift` (extend) | `fetchFeedWithBlocks() async throws -> FeedWithBlocks` |
| `…/ViewModels/HomeViewModel.swift` | `@MainActor final class` produces published `HomeUiState` |
| `…/ViewModels/BrowseViewModel.swift` | pagination + chip + поиск |
| `…/Views/HomeView.swift` | новый экран |
| `…/Views/BrowseView.swift` | новый экран |
| `…/Views/FavoritesView.swift` | grid + EmptyState |
| `…/Views/ProfileView.swift` | hero-секция + settings list |
| `…/Views/AboutView.swift` | минимальный about |

### iOS — изменяемые

| Path | Что |
|---|---|
| `…/Views/TabContainer.swift` | реальная 4-таб навигация, `TabView` с `NavigationStack` per tab |
| `…/UGamesApp.swift` | wire-up VMs, маршрутизация Game/Auth/Logs (deep-link сохраняется) |

### iOS — удаляемые

| Path | Когда |
|---|---|
| `…/Views/CatalogView.swift` | в конце фазы (вместе с `ProfileSheet`) |

---

## Data shapes

### Android

```kotlin
// catalog/FeedBlock.kt
data class FeedBlock(
    val type: String,    // "categorized" / "suggested" / "promo" / …
    val size: String?,   // "l" / "s" / null
    val title: String,
    val items: List<Game>,
)

data class FeedWithBlocks(
    val blocks: List<FeedBlock>,
    val flatGames: List<Game>,
    val genres: List<String>,    // из siteNavigationLinks.categories[].title
    val nextPageId: String?,
    val hasNext: Boolean,
)
```

```kotlin
// ui/home/HomeUiState.kt
data class HomeUiState(
    val isLoading: Boolean = false,
    val error: String? = null,
    val hero: Game? = null,
    val continueRow: List<Game> = emptyList(),
    val favoritesRow: List<Game> = emptyList(),
    val spotlight: SpotlightBlock? = null,
    val genreRows: List<GenreRow> = emptyList(),
    val profile: UserProfile = UserProfile(false, "", "", "", false),
)

data class SpotlightBlock(val title: String, val games: List<Game>)
data class GenreRow(val title: String, val games: List<Game>)
```

```kotlin
// ui/browse/BrowseUiState.kt
data class BrowseUiState(
    val mode: BrowseMode = BrowseMode.Feed,
    val games: List<Game> = emptyList(),
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val hasMore: Boolean = false,
    val nextPageId: String? = null,
    val error: String? = null,
    val searchQuery: String = "",
    val genres: List<String> = emptyList(),
    val selectedGenre: String? = null,   // null = "All"
)

enum class BrowseMode { Feed, Search }
```

### iOS — те же поля, формат struct/enum.

```swift
// Catalog/FeedBlock.swift
struct FeedBlock {
    let type: String
    let size: String?
    let title: String
    let items: [Game]
}

struct FeedWithBlocks {
    let blocks: [FeedBlock]
    let flatGames: [Game]
    let genres: [String]
    let nextPageId: String?
    let hasNext: Bool
}
```

`HomeViewModel` (iOS) публикует те же логические поля как `@Published`-свойства.

---

## Hero / Spotlight selection rules (общие, реализуем одинаково)

Из `FeedWithBlocks.blocks`:
1. **Hero** = первая `Game` из первого блока, у которого `type == "categorized"` И `size == "l"`. Fallback: `flatGames.maxByOrNull { it.ratingCount }`. Если и flatGames пуст — `null` (Skeleton).
2. **Spotlight** = первый блок с `type == "categorized"` И `size == "s"` И `items.size >= 5`, который ещё не использован в Hero/genreRows. `SpotlightBlock(title=block.title, games=block.items)`.
3. **Genre rows** = все `categorized`-блоки, кроме того, что попал в Spotlight. Hero-source-блок оставляем (его остальные items идут в genreRow). Каждый блок → `GenreRow(title=block.title, games=block.items)`. Лимит 8 рядов на страницу (защита от длинного scroll).
4. **Continue / Favorites rows** — берутся из локальных стораджей (`recents` / `favorites`), не из feed.

---

## Tab navigation modeling

Spec требует, чтобы каждый таб владел собственным push-stack-ом (Game/Auth/Logs/About не подменяли таб), и tab-bar скрывался поверх pushed-экрана. Минимально-инвазивная реализация:

- В `TabContainer` храним per-tab `MutableState<TabRoute>` (sealed: `Root | Game | Auth | Logs | About`). Активный таб рендерит свой Root; если у него ненулевой `pushed`, рендерим pushed-экран и `hideBar = true`.
- Switch таба не сбрасывает back-stacks других табов.
- Deep-link и intent-Game на старте уходит в `Home`-таб (соответствует текущему поведению `MainActivity`).

iOS: `TabView { NavigationStack(path: $homePath) { … } … }` per tab, `NavigationLink(value: …)` push-ит в свой stack.

---

## Task overview

| # | Task | Platform | Verify |
|---|---|---|---|
| 1 | `FeedBlock` data class | Android | компилируется |
| 2 | `CatalogApi.firstFeedPageWithBlocks` + genre parsing | Android | компилируется + smoke-парсинг live response (через `assembleDebug` + ручной запуск) |
| 3 | `CatalogRepository.firstFeedWithBlocks` обёртка | Android | компилируется |
| 4 | `HomeUiState` + sub-types | Android | компилируется |
| 5 | `HomeViewModel` (loads feed-with-blocks, exposes state) | Android | компилируется |
| 6 | `HomeScreen` (header, search-stub, Hero, rows, Spotlight) | Android | preview + запуск таба |
| 7 | `BrowseUiState` | Android | компилируется |
| 8 | `BrowseViewModel` (pagination + chip-фильтр + search) | Android | компилируется |
| 9 | `BrowseScreen` (sticky topbar + chips + grid) | Android | preview + запуск таба |
| 10 | `FavoritesScreen` (grid + EmptyState; reuses repo) | Android | preview + запуск таба |
| 11 | `ProfileViewModel` + `ProfileScreen` (hero-секция + settings list) | Android | preview + запуск таба |
| 12 | `AboutScreen` | Android | preview |
| 13 | `TabContainer` — реальная 4-таб нав с per-tab push-stack | Android | переключение табов работает, push Game/Auth/Logs скрывает bar |
| 14 | `MainActivity` wiring (создание VMs, передача в TabContainer) | Android | приложение запускается, deep-link работает, golden path (Home → Game → Back; Browse → search; Profile → Sign out) |
| 15 | Удалить `CatalogScreen.kt` + `CatalogViewModel.kt` | Android | сборка зелёная, никаких ссылок не осталось |
| 16 | iOS: `FeedBlock` + `FeedWithBlocks` | iOS | компилируется |
| 17 | iOS: `CatalogService.fetchFeedWithBlocks` + genre parsing | iOS | компилируется |
| 18 | iOS: `HomeViewModel` | iOS | компилируется |
| 19 | iOS: `HomeView` | iOS | preview + запуск таба |
| 20 | iOS: `BrowseViewModel` | iOS | компилируется |
| 21 | iOS: `BrowseView` | iOS | preview + запуск таба |
| 22 | iOS: `FavoritesView` | iOS | preview + запуск таба |
| 23 | iOS: `ProfileView` | iOS | preview + запуск таба |
| 24 | iOS: `AboutView` | iOS | preview |
| 25 | iOS: `TabContainer` — реальная 4-таб навигация с `NavigationStack` per tab | iOS | переключение табов + push корректны |
| 26 | iOS: `UGamesApp` wiring | iOS | приложение запускается, deep-link работает, golden path |
| 27 | Удалить `CatalogView.swift` (включая `ProfileSheet`) | iOS | сборка зелёная |
| 28 | Финальный `git push` + PR | both | зелёный билд CI (если есть), визуальная проверка обоих приложений |

---

## Detailed tasks

> Стиль: каждый таск перечисляет **Files**, иногда показывает критичный код (новые data-классы, парсинг блоков, не-очевидный VM-flow), но не дублирует boilerplate Compose/SwiftUI — паттерны те же, что в Phase 1.

### Task 1: Android — `FeedBlock`

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/catalog/FeedBlock.kt`

```kotlin
package games.yandex.wrap.catalog

data class FeedBlock(
    val type: String,
    val size: String?,
    val title: String,
    val items: List<Game>,
)

data class FeedWithBlocks(
    val blocks: List<FeedBlock>,
    val flatGames: List<Game>,
    val genres: List<String>,
    val nextPageId: String?,
    val hasNext: Boolean,
)
```

- [ ] Build: `cd android && ./gradlew :app:compileDebugKotlin`
- [ ] Commit: `feat(android): add FeedBlock + FeedWithBlocks types`

### Task 2: Android — `CatalogApi.firstFeedPageWithBlocks` + genre parsing

**Files:**
- Modify: `android/app/src/main/kotlin/games/yandex/wrap/catalog/CatalogApi.kt`

Add a new method that calls the same `FEED_URL` but **preserves block structure**, plus extracts `siteNavigationLinks.categories[].title` for the genre list. Reuse `itemToGame` and the existing dedupe in `parseFeedItems` for the flat list. Block titles default to `""` (мы их в UI скрываем, если пусто).

```kotlin
suspend fun firstFeedPageWithBlocks(
    gamesPerPage: Int = 24,
    lang: String = "en",
    clientWidth: Int = 412,
    clientHeight: Int = 915,
): FeedWithBlocks {
    val response: JsonObject = httpClient.get(FEED_URL) {
        parameter("with_promos", "true")
        parameter("lang", lang)
        parameter("games_count", gamesPerPage.toString())
        parameter("categorized_size", "5")
        parameter("with_recent_games", "true")
        parameter("platform", "android_other")
        parameter("client_width", clientWidth.toString())
        parameter("client_height", clientHeight.toString())
        mobileHeaders()
    }.body()

    val feedArr = response["feed"] as? JsonArray ?: JsonArray(emptyList())
    val blocks = feedArr.mapNotNull { el ->
        val obj = el as? JsonObject ?: return@mapNotNull null
        val type = obj["type"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
        val size = obj["size"]?.jsonPrimitive?.contentOrNull
        val title = obj["title"]?.jsonPrimitive?.contentOrNull.orEmpty()
        val items = (obj["items"] as? JsonArray ?: JsonArray(emptyList()))
            .mapNotNull { itemToGame(it as? JsonObject ?: return@mapNotNull null) }
        if (items.isEmpty()) null else FeedBlock(type, size, title, items)
    }
    val flat = run {
        val seen = mutableSetOf<Long>()
        buildList { for (b in blocks) for (g in b.items) if (seen.add(g.appId)) add(g) }
    }
    val pageInfo = response["pageInfo"] as? JsonObject
    val nextPageId = pageInfo?.get("nextPageId")?.jsonPrimitive?.contentOrNull
    val hasNext = pageInfo?.get("hasNextPage")?.jsonPrimitive?.booleanOrNull ?: (nextPageId != null)

    val nav = response["siteNavigationLinks"] as? JsonObject
    val cats = (nav?.get("categories") as? JsonArray ?: JsonArray(emptyList()))
        .mapNotNull {
            val o = it as? JsonObject ?: return@mapNotNull null
            o["title"]?.jsonPrimitive?.contentOrNull
                ?: o["name"]?.jsonPrimitive?.contentOrNull
        }

    return FeedWithBlocks(
        blocks = blocks,
        flatGames = flat,
        genres = cats,
        nextPageId = nextPageId,
        hasNext = hasNext,
    )
}
```

- [ ] Build: `:app:compileDebugKotlin`
- [ ] Commit: `feat(android): add firstFeedPageWithBlocks API + genre parsing`

### Task 3: Android — `CatalogRepository.firstFeedWithBlocks`

**Files:**
- Modify: `android/app/src/main/kotlin/games/yandex/wrap/catalog/CatalogRepository.kt`

Wrapper:

```kotlin
suspend fun firstFeedWithBlocks(gamesPerPage: Int = 24): FeedWithBlocks {
    val resp = api.firstFeedPageWithBlocks(gamesPerPage = gamesPerPage)
    if (resp.flatGames.isNotEmpty()) {
        cache.upsertAll(resp.flatGames.map { it.toEntity() })
    }
    return resp
}
```

`Game.toEntity` уже есть как private extension в файле — reuse.

- [ ] Build
- [ ] Commit: `feat(android): repository.firstFeedWithBlocks wrapper`

### Task 4: Android — `HomeUiState`

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/home/HomeUiState.kt`

```kotlin
package games.yandex.wrap.ui.home

import games.yandex.wrap.catalog.Game
import games.yandex.wrap.catalog.UserProfile

data class HomeUiState(
    val isLoading: Boolean = false,
    val error: String? = null,
    val hero: Game? = null,
    val continueRow: List<Game> = emptyList(),
    val favoritesRow: List<Game> = emptyList(),
    val spotlight: SpotlightBlock? = null,
    val genreRows: List<GenreRow> = emptyList(),
    val profile: UserProfile = UserProfile(false, "", "", "", false),
)

data class SpotlightBlock(val title: String, val games: List<Game>)
data class GenreRow(val title: String, val games: List<Game>)
```

- [ ] Build
- [ ] Commit: `feat(android): add HomeUiState`

### Task 5: Android — `HomeViewModel`

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/home/HomeViewModel.kt`

Берёт `CatalogRepository`, грузит feed-with-blocks, вычисляет hero/spotlight/genreRows по правилам выше, мерджит recents/favorites.

```kotlin
package games.yandex.wrap.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import games.yandex.wrap.catalog.CatalogRepository
import games.yandex.wrap.catalog.FeedBlock
import games.yandex.wrap.catalog.Game
import games.yandex.wrap.catalog.UserProfile
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class HomeViewModel(private val repository: CatalogRepository) : ViewModel() {
    private val _state = MutableStateFlow(HomeUiState())
    val state: StateFlow<HomeUiState> = _state.asStateFlow()

    val recent: StateFlow<List<Game>> = repository.recentGames()
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    val favorites: StateFlow<List<Game>> = repository.favoritesAsGames()
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    init {
        refresh()
        viewModelScope.launch {
            // keep continue/favorites rows live as stores change
            combine(recent, favorites) { r, f -> r to f }.collect { (r, f) ->
                _state.update { it.copy(continueRow = r.take(12), favoritesRow = f.take(12)) }
            }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            val result = runCatching { repository.firstFeedWithBlocks() }
            result.fold(
                onSuccess = { feed ->
                    val (hero, spotlight, genreRows) = digest(feed.blocks, feed.flatGames)
                    _state.update {
                        it.copy(
                            isLoading = false,
                            error = null,
                            hero = hero,
                            spotlight = spotlight,
                            genreRows = genreRows,
                        )
                    }
                },
                onFailure = { err ->
                    _state.update { it.copy(isLoading = false, error = err.message) }
                },
            )
            refreshProfile()
        }
    }

    private fun refreshProfile() {
        viewModelScope.launch {
            val p = runCatching { repository.userProfile() }.getOrNull()
            if (p != null) _state.update { it.copy(profile = p) }
        }
    }

    private fun digest(
        blocks: List<FeedBlock>,
        flat: List<Game>,
    ): Triple<Game?, SpotlightBlock?, List<GenreRow>> {
        val heroBlock = blocks.firstOrNull { it.type == "categorized" && it.size == "l" }
        val hero = heroBlock?.items?.firstOrNull()
            ?: flat.maxByOrNull { it.ratingCount }
        val spotlightBlock = blocks.firstOrNull {
            it.type == "categorized" && it.size == "s" && it.items.size >= 5
        }
        val spotlight = spotlightBlock?.let { SpotlightBlock(it.title, it.games(spotlightBlock)) }
        val genreRows = blocks
            .filter { it.type == "categorized" && it !== spotlightBlock }
            .take(8)
            .map { b ->
                val items = if (b === heroBlock) b.items.drop(1) else b.items
                GenreRow(b.title, items)
            }
            .filter { it.games.isNotEmpty() }
        return Triple(hero, spotlight, genreRows)
    }

    private fun FeedBlock.games(block: FeedBlock): List<Game> = block.items
}
```

- [ ] Build
- [ ] Commit: `feat(android): add HomeViewModel with hero/spotlight/genre digest`

### Task 6: Android — `HomeScreen`

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/home/HomeScreen.kt`

Лэйаут (`LazyColumn`):

1. Header — `padding(top = WindowInsets.statusBars + 12.dp, horizontal = 14.dp)`. `Column { Text(eyebrow, UGType.Label) ; Row { Text("Good evening", TitleL) ; Spacer(weight=1) ; AvatarButton(profile, onClick = onProfileClick) } }`. Eyebrow = `"${dayOfWeek} · TOP PICKS"` через `LocalDate.now().dayOfWeek.name.lowercase().capitalize()`. Greeting — функция от `LocalTime.now().hour`.
2. Search-stub — pseudo-input «🔍 Search games», `Modifier.clickable { onOpenBrowse() }`.
3. Hero — `state.hero?.let { HeroSection(it, onPlay = { onGameClick(it) }, onFavorite = { vm.toggleFavorite(it) }, onShare = { onShare(it) }) } ?: HeroSkeleton()`.
4. Continue row — `if (continueRow.isNotEmpty()) RowSection("Continue playing", lazyRow of WideGameCard)`.
5. Favorites row — то же для `favoritesRow`.
6. Spotlight — `state.spotlight?.let { StoryCard(title=it.title, subtitle="SPOTLIGHT · ${it.title.uppercase()}", games=it.games.take(3), onClick = { onOpenBrowseFiltered(it.title) }) }`. Если `null` — секция отсутствует.
7. Genre rows — `state.genreRows.forEach { row -> SectionHeader(row.title, onSeeAll = { onOpenBrowseFiltered(row.title) }) ; lazyRow of SquareGameCard }`.
8. `Spacer(height = 96.dp)` под floating tab-bar.

Skeleton-блок: `Box(.fillMaxWidth().height(300.dp).clip(RoundedCornerShape(22.dp))).background(UGColors.Elevated)` с `Skeleton`-shimmer. Используем существующий `Skeleton` компонент.

Сигнатура:

```kotlin
@Composable
fun HomeScreen(
    viewModel: HomeViewModel,
    onGameClick: (Game) -> Unit,
    onOpenBrowse: () -> Unit,                   // search-stub click
    onOpenBrowseFiltered: (String) -> Unit,     // genre "See all" / spotlight click
    onProfileClick: () -> Unit,                 // когда tab-нав не кликабельна (long-press для logs остаётся в Profile-табе)
    onShareGame: (Game) -> Unit,
)
```

Compose-код пишется по паттерну `Hero.kt`/`StoryCard.kt`. Модификаторы — `UGColors.Bg0` фон, `WindowInsets.statusBars` верхний padding.

- [ ] Build + ручная проверка preview
- [ ] Commit: `feat(android): add HomeScreen (hero + rows + spotlight)`

### Task 7: Android — `BrowseUiState`

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/browse/BrowseUiState.kt`

```kotlin
package games.yandex.wrap.ui.browse

import games.yandex.wrap.catalog.Game

data class BrowseUiState(
    val mode: BrowseMode = BrowseMode.Feed,
    val games: List<Game> = emptyList(),
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val hasMore: Boolean = false,
    val nextPageId: String? = null,
    val error: String? = null,
    val searchQuery: String = "",
    val genres: List<String> = emptyList(),
    val selectedGenre: String? = null,
)

enum class BrowseMode { Feed, Search }
```

- [ ] Build
- [ ] Commit: `feat(android): add BrowseUiState`

### Task 8: Android — `BrowseViewModel`

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/browse/BrowseViewModel.kt`

Логика — копия `CatalogViewModel`, но без `recent`/`favorites`/`profile` (это не задача Browse), плюс:
- `setGenre(String?)` — клиентский фильтр по `Game.categories.contains(genre, ignoreCase=true)`. При пустом `selectedGenre` — feed как есть.
- `genres` загружается одним вызовом `repository.firstFeedWithBlocks()` (берём `feed.genres`).
- `loadMore()` использует `repository.nextFeedPage(pageId)` (тот же flat-pagination что и сейчас).

Сигнатура:

```kotlin
class BrowseViewModel(private val repository: CatalogRepository) : ViewModel() {
    private val _state = MutableStateFlow(BrowseUiState())
    val state: StateFlow<BrowseUiState> = _state.asStateFlow()

    val favoriteIds: StateFlow<Set<Long>> = repository.favoriteIds()
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptySet())

    init { refresh() }

    fun refresh() { /* fetch firstFeedWithBlocks → set games + genres */ }
    fun loadMore() { /* nextFeedPage */ }
    fun onSearchChange(q: String) { /* debounce 400ms */ }
    fun submitSearch() { /* immediate */ }
    fun setGenre(g: String?) { _state.update { it.copy(selectedGenre = g) } }
    fun toggleFavorite(g: Game) { viewModelScope.launch { runCatching { repository.toggleFavorite(g) } } }

    fun visibleGames(state: BrowseUiState): List<Game> {
        if (state.mode == BrowseMode.Search) return state.games
        val sel = state.selectedGenre ?: return state.games
        return state.games.filter { g -> g.categories.any { it.equals(sel, ignoreCase = true) } }
    }
}
```

- [ ] Build
- [ ] Commit: `feat(android): add BrowseViewModel`

### Task 9: Android — `BrowseScreen`

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/browse/BrowseScreen.kt`

Лэйаут — `Column`:
1. Sticky topbar — `OutlinedTextField` (search) + правый аватар (`profile` берётся из constructor-arg или из Home-VM-shared; для Phase 2 — берём `UserProfile.anonymous` placeholder, профильная инфа на Profile-табе). Avatar клик → `onProfileClick()`.
2. Sticky chips-row — `GenreChipRow(state.genres, state.selectedGenre, onSelect = vm::setGenre)`. Показывается только в `Mode.Feed`.
3. Grid — `LazyVerticalGrid(GridCells.Adaptive(160.dp))` из `TileGameCard`. Pagination через `snapshotFlow` на `gridState.layoutInfo` (тот же паттерн, что сейчас в CatalogScreen). Пустой state — `EmptyState` или текст "No games match \"…\"".

Сигнатура:

```kotlin
@Composable
fun BrowseScreen(
    viewModel: BrowseViewModel,
    profile: UserProfile,
    onGameClick: (Game) -> Unit,
    onProfileClick: () -> Unit,
    initialGenre: String? = null,
)
```

- [ ] Build + preview
- [ ] Commit: `feat(android): add BrowseScreen (chips + grid + search)`

### Task 10: Android — `FavoritesScreen`

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/favorites/FavoritesScreen.kt`

Использует `CatalogRepository.favoritesAsGames()` напрямую через переданный `Flow<List<Game>>` (или мини-VM). Достаточно `@Composable fun FavoritesScreen(games: List<Game>, onGameClick, onToggle, onBrowse)`. Header — «Favorites · {N}» (Title-M). Если `games.isEmpty()` — `EmptyState(icon=heart, title="No favorites yet", body="Tap ♥ on any game to save it", ctaLabel="Browse games", onCta=onBrowse)`. Иначе — `LazyVerticalGrid(160.dp)` из `TileGameCard`.

- [ ] Build + preview
- [ ] Commit: `feat(android): add FavoritesScreen`

### Task 11: Android — `ProfileScreen` + `ProfileViewModel`

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/profile/ProfileViewModel.kt`
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/profile/ProfileScreen.kt`

VM:

```kotlin
class ProfileViewModel(private val repository: CatalogRepository) : ViewModel() {
    private val _profile = MutableStateFlow(UserProfile(false, "", "", "", false))
    val profile: StateFlow<UserProfile> = _profile.asStateFlow()

    init { refresh() }

    fun refresh() {
        viewModelScope.launch {
            val p = runCatching { repository.userProfile() }.getOrNull()
            if (p != null) _profile.value = p
        }
    }

    fun signOut(onDone: () -> Unit) {
        viewModelScope.launch {
            runCatching { repository.clearSession() }
            _profile.value = UserProfile(false, "", "", "", false)
            onDone()
        }
    }
}
```

Screen:
- Hero-section: 96dp avatar (gradient ring если `hasYaPlus`), display-name, login (если отличается).
- Plus-pill (`accent`-tint).
- Settings — `elevated` (UGColors.Elevated) карточки с разделителями:
  - `Sign in` (если не авторизован, `accent.gradient` button) — `onLoginClick`
  - `Sign out` (если авторизован, `Danger`-цвет) — `vm.signOut()` + on-done route to anonymous
  - `Diagnostic logs` → `onLogsClick`
  - `About` → `onAboutClick`
- Long-press на аватаре — `onLogsClick` (backup-вход в Logs, как было).

Сигнатура:

```kotlin
@Composable
fun ProfileScreen(
    viewModel: ProfileViewModel,
    onLoginClick: () -> Unit,
    onLogsClick: () -> Unit,
    onAboutClick: () -> Unit,
)
```

- [ ] Build + preview
- [ ] Commit: `feat(android): add ProfileScreen + ProfileViewModel`

### Task 12: Android — `AboutScreen`

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/profile/AboutScreen.kt`

Минимальный экран: TopBar с back-кнопкой; ниже — иконка приложения 64dp, app name «U-Games», версия (`BuildConfig.VERSION_NAME`), ссылка на GitHub (текст-кнопка, открывает `https://github.com/<repo>` через `Intent.ACTION_VIEW`).

```kotlin
@Composable
fun AboutScreen(onBack: () -> Unit) { ... }
```

- [ ] Build + preview
- [ ] Commit: `feat(android): add AboutScreen`

### Task 13: Android — `TabContainer` (4-tab nav with per-tab push)

**Files:**
- Modify: `android/app/src/main/kotlin/games/yandex/wrap/ui/TabContainer.kt`

Полная переработка. Хранит per-tab pushed-route. Bar скрывается, если у активного таба есть pushed-экран.

```kotlin
sealed interface TabPushed {
    data object None : TabPushed
    data class Game(val appId: Long, val title: String) : TabPushed
    data object Auth : TabPushed
    data object Logs : TabPushed
    data object About : TabPushed
}

@Composable
fun TabContainer(
    home: @Composable (push: (TabPushed) -> Unit) -> Unit,
    browse: @Composable (push: (TabPushed) -> Unit) -> Unit,
    favorites: @Composable (push: (TabPushed) -> Unit) -> Unit,
    profile: @Composable (push: (TabPushed) -> Unit) -> Unit,
    pushedHost: @Composable (TabPushed, onPop: () -> Unit) -> Unit,
) {
    var selected by remember { mutableStateOf("home") }
    var homePushed by remember { mutableStateOf<TabPushed>(TabPushed.None) }
    var browsePushed by remember { mutableStateOf<TabPushed>(TabPushed.None) }
    var favoritesPushed by remember { mutableStateOf<TabPushed>(TabPushed.None) }
    var profilePushed by remember { mutableStateOf<TabPushed>(TabPushed.None) }

    val pushed: TabPushed = when (selected) {
        "home" -> homePushed
        "browse" -> browsePushed
        "favorites" -> favoritesPushed
        else -> profilePushed
    }

    Box(Modifier.fillMaxSize()) {
        // Render the selected tab's root or its pushed screen
        when (selected) {
            "home" -> if (homePushed is TabPushed.None) home { homePushed = it }
                       else pushedHost(homePushed) { homePushed = TabPushed.None }
            "browse" -> if (browsePushed is TabPushed.None) browse { browsePushed = it }
                         else pushedHost(browsePushed) { browsePushed = TabPushed.None }
            "favorites" -> if (favoritesPushed is TabPushed.None) favorites { favoritesPushed = it }
                            else pushedHost(favoritesPushed) { favoritesPushed = TabPushed.None }
            "profile" -> if (profilePushed is TabPushed.None) profile { profilePushed = it }
                          else pushedHost(profilePushed) { profilePushed = TabPushed.None }
        }
        if (pushed is TabPushed.None) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
                FloatingTabBar(
                    tabs = listOf(
                        UGTab("home", "Home", Icons.Filled.Home),
                        UGTab("browse", "Browse", Icons.Filled.GridView),
                        UGTab("favorites", "Favorites", Icons.Filled.Favorite),
                        UGTab("profile", "Profile", Icons.Filled.AccountCircle),
                    ),
                    selectedKey = selected,
                    onSelect = { selected = it },
                )
            }
        }
    }
}
```

- [ ] Build
- [ ] Commit: `feat(android): TabContainer with per-tab push stacks`

### Task 14: Android — `MainActivity` wiring

**Files:**
- Modify: `android/app/src/main/kotlin/games/yandex/wrap/MainActivity.kt`

Создаём 4 VM-а: `HomeViewModel`, `BrowseViewModel`, `ProfileViewModel`, и переиспользуем `CatalogRepository`/`FavoritesDao` для `FavoritesScreen`. Передаём в `TabContainer`. `pushedHost` мапит:
- `TabPushed.Game` → `GameScreen`
- `TabPushed.Auth` → `AuthScreen`
- `TabPushed.Logs` → `LogsScreen`
- `TabPushed.About` → `AboutScreen`

Deep-link на старте — pushes `TabPushed.Game` в `home`-таб (выбираем `selected = "home"` сразу + `homePushed = Game(...)`).

Удаляем все ссылки на `CatalogScreen`/`CatalogViewModel`.

`onGameClick` теперь вызывает `repository.recordOpen(game)` напрямую (вынести `recordGameOpen` из ViewModel в callback, сделанный из `MainActivity`-scope: `lifecycleScope.launch { repository.recordOpen(game) }`).

- [ ] Build
- [ ] Запуск приложения, golden path: Home рендерит Hero/rows/Spotlight; нажатие на Hero/карточку открывает Game; Back возвращает в Home без потери scroll-state; переключение на Browse работает search+chips; Favorites показывает grid или EmptyState; Profile показывает hero+settings, Sign out работает; About открывается. Deep-link `ugames://app/123` запускает игру в home-табе.
- [ ] Commit: `feat(android): wire 4-tab nav with HomeViewModel + BrowseViewModel + ProfileViewModel`

### Task 15: Android — Удалить `CatalogScreen.kt` + `CatalogViewModel.kt`

**Files:**
- Delete: `android/app/src/main/kotlin/games/yandex/wrap/ui/CatalogScreen.kt`
- Delete: `android/app/src/main/kotlin/games/yandex/wrap/ui/CatalogViewModel.kt`

- [ ] Build (зелёная — никаких ссылок не осталось, потому что Task 14 их уже разорвал)
- [ ] Commit: `chore(android): remove old CatalogScreen + CatalogViewModel`

---

### Task 16: iOS — `FeedBlock` + `FeedWithBlocks`

**Files:**
- Create: `ios/UGames/Catalog/FeedBlock.swift`

```swift
import Foundation

struct FeedBlock {
    let type: String
    let size: String?
    let title: String
    let items: [Game]
}

struct FeedWithBlocks {
    let blocks: [FeedBlock]
    let flatGames: [Game]
    let genres: [String]
    let nextPageId: String?
    let hasNext: Bool
}
```

- [ ] Build (XcodeGen → `cd ios && xcodegen` если project.yml менялся — он не менялся, но новый файл в `Catalog/` подхватится автоматически по glob), затем `xcodebuild … build`.
- [ ] Commit: `feat(ios): add FeedBlock + FeedWithBlocks`

### Task 17: iOS — `CatalogService.fetchFeedWithBlocks` + genre parsing

**Files:**
- Modify: `ios/UGames/Catalog/CatalogService.swift`

Добавить метод:

```swift
func fetchFeedWithBlocks(gamesPerPage: Int = 24, lang: String = "en") async throws -> FeedWithBlocks {
    var components = URLComponents(string: "https://yandex.com/games/api/catalogue/v2/feed/")!
    components.queryItems = [
        URLQueryItem(name: "with_promos", value: "true"),
        URLQueryItem(name: "lang", value: lang),
        URLQueryItem(name: "games_count", value: String(gamesPerPage)),
        URLQueryItem(name: "categorized_size", value: "5"),
        URLQueryItem(name: "with_recent_games", value: "true"),
        URLQueryItem(name: "platform", value: "ios"),
        URLQueryItem(name: "client_width", value: "390"),
        URLQueryItem(name: "client_height", value: "844"),
    ]
    var request = URLRequest(url: components.url!)
    request.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, _) = try await URLSession.shared.data(for: request)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let feed = root["feed"] as? [[String: Any]]
    else { return FeedWithBlocks(blocks: [], flatGames: [], genres: [], nextPageId: nil, hasNext: false) }

    var blocks: [FeedBlock] = []
    var seen = Set<Int64>()
    var flat: [Game] = []
    for raw in feed {
        guard let type = raw["type"] as? String else { continue }
        let size = raw["size"] as? String
        let title = (raw["title"] as? String) ?? ""
        let items = ((raw["items"] as? [[String: Any]]) ?? []).compactMap(GameDecoderPublic.parse)
        if items.isEmpty { continue }
        blocks.append(FeedBlock(type: type, size: size, title: title, items: items))
        for g in items where seen.insert(g.appId).inserted { flat.append(g) }
    }
    let pageInfo = root["pageInfo"] as? [String: Any]
    let nextPageId = pageInfo?["nextPageId"] as? String
    let hasNext = (pageInfo?["hasNextPage"] as? Bool) ?? (nextPageId != nil)
    let nav = root["siteNavigationLinks"] as? [String: Any]
    let cats = ((nav?["categories"] as? [[String: Any]]) ?? []).compactMap {
        ($0["title"] as? String) ?? ($0["name"] as? String)
    }
    return FeedWithBlocks(blocks: blocks, flatGames: flat, genres: cats, nextPageId: nextPageId, hasNext: hasNext)
}
```

`GameDecoder` сейчас private — выносим его `parse` метод в `internal` (или дублируем парсер, но проще expose). Минимально: убираем `private` у `GameDecoder` и у `parse` — превращаем в `enum GameDecoder { static func parse(_:) -> Game? ; static func flatten(_:) }`. Имя `GameDecoderPublic` в коде выше — placeholder; реально использовать `GameDecoder.parse`.

- [ ] Build
- [ ] Commit: `feat(ios): add fetchFeedWithBlocks + genre parsing`

### Task 18: iOS — `HomeViewModel`

**Files:**
- Create: `ios/UGames/ViewModels/HomeViewModel.swift`

```swift
import Foundation
import Combine

struct SpotlightBlock: Equatable { let title: String; let games: [Game] }
struct GenreRow: Equatable { let title: String; let games: [Game] }

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?
    @Published private(set) var hero: Game?
    @Published private(set) var continueRow: [Game] = []
    @Published private(set) var favoritesRow: [Game] = []
    @Published private(set) var spotlight: SpotlightBlock?
    @Published private(set) var genreRows: [GenreRow] = []
    @Published private(set) var profile: UserProfile = .anonymous

    private let service: CatalogService
    private let recents: RecentGamesStore
    private let favs: FavoritesStore
    private var cancellables = Set<AnyCancellable>()

    init(service: CatalogService, recents: RecentGamesStore, favorites: FavoritesStore) {
        self.service = service
        self.recents = recents
        self.favs = favorites
        recents.$games.receive(on: RunLoop.main).sink { [weak self] g in self?.continueRow = Array(g.prefix(12)) }.store(in: &cancellables)
        favorites.$games.receive(on: RunLoop.main).sink { [weak self] g in self?.favoritesRow = Array(g.prefix(12)) }.store(in: &cancellables)
        service.$profile.receive(on: RunLoop.main).sink { [weak self] p in self?.profile = p }.store(in: &cancellables)
    }

    func refresh() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let feed = try await service.fetchFeedWithBlocks()
            digest(blocks: feed.blocks, flat: feed.flatGames)
        } catch {
            self.error = error.localizedDescription
        }
        await service.refreshProfile()
    }

    private func digest(blocks: [FeedBlock], flat: [Game]) {
        let heroBlock = blocks.first(where: { $0.type == "categorized" && $0.size == "l" })
        hero = heroBlock?.items.first ?? flat.max(by: { $0.ratingCount < $1.ratingCount })
        let spotlightBlock = blocks.first(where: { $0.type == "categorized" && $0.size == "s" && $0.items.count >= 5 })
        spotlight = spotlightBlock.map { SpotlightBlock(title: $0.title, games: $0.items) }
        let rows = blocks
            .filter { $0.type == "categorized" }
            .filter { spotlightBlock == nil || $0.title != spotlightBlock!.title }
            .prefix(8)
            .map { b -> GenreRow in
                let items = (b.title == heroBlock?.title) ? Array(b.items.dropFirst()) : b.items
                return GenreRow(title: b.title, games: items)
            }
            .filter { !$0.games.isEmpty }
        genreRows = Array(rows)
    }
}
```

- [ ] Build
- [ ] Commit: `feat(ios): add HomeViewModel`

### Task 19: iOS — `HomeView`

**Files:**
- Create: `ios/UGames/Views/HomeView.swift`

`ScrollView { LazyVStack(spacing: 18) { Header ; SearchStub ; Hero ; ContinueRow ; FavoritesRow ; Spotlight ; GenreRows ; Spacer(96) } }`. Используем `HeroSection`, `WideGameCard`, `StoryCard`, `SquareGameCard` из Phase 1 (они в `Components/`). Top padding — `.safeAreaInset(edge: .top)` для greeting. Фон `UGColor.bg0`.

Сигнатура:

```swift
struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    let onGameClick: (Game) -> Void
    let onOpenBrowse: () -> Void
    let onOpenBrowseFiltered: (String) -> Void
    let onProfileClick: () -> Void
    let onShareGame: (Game) -> Void
    var body: some View { … }
}
```

`.task { await viewModel.refresh() }`. `.refreshable { await viewModel.refresh() }`.

- [ ] Build + preview
- [ ] Commit: `feat(ios): add HomeView`

### Task 20: iOS — `BrowseViewModel`

**Files:**
- Create: `ios/UGames/ViewModels/BrowseViewModel.swift`

```swift
@MainActor
final class BrowseViewModel: ObservableObject {
    enum Mode { case feed, search }

    @Published private(set) var games: [Game] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var hasMore: Bool = false
    @Published private(set) var error: String?
    @Published var searchQuery: String = "" { didSet { onQueryChanged(searchQuery) } }
    @Published private(set) var genres: [String] = []
    @Published var selectedGenre: String? = nil
    @Published private(set) var mode: Mode = .feed

    private let service: CatalogService
    private var nextPageId: String?
    private var searchTask: Task<Void, Never>?

    init(service: CatalogService) { self.service = service }

    func refresh() async { /* fetchFeedWithBlocks → games=feed.flatGames, genres=feed.genres */ }
    func loadMore() { /* uses nextPageId via existing fetchFeed */ }
    private func onQueryChanged(_ q: String) { /* debounce 0.4s */ }
    func submitSearch() { /* immediate */ }

    var visibleGames: [Game] {
        guard mode == .feed, let g = selectedGenre else { return games }
        return games.filter { $0.categories.contains(where: { $0.localizedCaseInsensitiveCompare(g) == .orderedSame }) }
    }
}
```

Note: `fetchFeed(pageId:)` сейчас private у CatalogService — нужно либо вынести в `internal func` (Swift не имеет такого, доступ файла), либо вынести `BrowseViewModel` в тот же модуль (он уже в том же таргете), либо просто сделать `fetchFeed` `func` без `private`. Меняем на `func fetchFeed(pageId: String?, gamesPerPage: Int = 24, lang: String = "en") async throws -> FeedPage` (без private), и `FeedPage` — поднимаем в файловый scope.

- [ ] Build
- [ ] Commit: `feat(ios): add BrowseViewModel`

### Task 21: iOS — `BrowseView`

**Files:**
- Create: `ios/UGames/Views/BrowseView.swift`

Layout:
```
VStack(spacing: 0) {
  TopBar (search field + avatar)        // .background(UGColor.bg0)
  GenreChipRow(state.genres, ...)       // только в .feed mode
  Grid (LazyVGrid adaptive 160pt) of TileGameCard
}
```

Pagination — `.onAppear` last cell, как сейчас.

- [ ] Build + preview
- [ ] Commit: `feat(ios): add BrowseView`

### Task 22: iOS — `FavoritesView`

**Files:**
- Create: `ios/UGames/Views/FavoritesView.swift`

```swift
struct FavoritesView: View {
    @ObservedObject var favorites: FavoritesStore
    let onGameClick: (Game) -> Void
    let onBrowse: () -> Void
    var body: some View {
        if favorites.games.isEmpty {
            EmptyState(systemIcon: "heart", title: "No favorites yet", message: "Tap ♥ on any game to save it", ctaLabel: "Browse games", onCta: onBrowse)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)], spacing: 12) {
                    ForEach(favorites.games) { g in
                        TileGameCard(game: g, isFavorite: true, onFavoriteToggle: { favorites.toggle(g) })
                            .onTapGesture { onGameClick(g) }
                    }
                }.padding(12).padding(.bottom, 96)
            }
        }
    }
}
```

(Убедиться, что `EmptyState` поддерживает CTA-параметры. Если нет — расширить минимально. Существующий `EmptyState.swift` уже принимает `cta`/`onCta` — проверить.)

- [ ] Build + preview
- [ ] Commit: `feat(ios): add FavoritesView`

### Task 23: iOS — `ProfileView`

**Files:**
- Create: `ios/UGames/Views/ProfileView.swift`

Reuse `service.profile`. Layout аналогичен `ProfileSheet` старого, но full-screen, с UGColor/UGFont, с разделом «Settings» (cards) и `About` row.

```swift
struct ProfileView: View {
    @ObservedObject var service: CatalogService
    let onLoginClick: () -> Void
    let onLogsClick: () -> Void
    let onAboutClick: () -> Void
    var body: some View { … }
}
```

`onLongPress` на аватар — `onLogsClick`.

- [ ] Build + preview
- [ ] Commit: `feat(ios): add ProfileView`

### Task 24: iOS — `AboutView`

**Files:**
- Create: `ios/UGames/Views/AboutView.swift`

```swift
struct AboutView: View {
    let onBack: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            HStack { Button("← Back", action: onBack); Spacer() }.padding()
            Image(systemName: "gamecontroller.fill").font(.system(size: 48)).foregroundColor(UGColor.accent)
            Text("U-Games").font(UGFont.titleL).foregroundColor(UGColor.textPrimary)
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                .font(UGFont.bodyS).foregroundColor(UGColor.textMuted)
            Link("View on GitHub", destination: URL(string: "https://github.com/")!)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(UGColor.bg0)
    }
}
```

- [ ] Build + preview
- [ ] Commit: `feat(ios): add AboutView`

### Task 25: iOS — `TabContainer` (real 4-tab nav)

**Files:**
- Modify: `ios/UGames/Views/TabContainer.swift`

```swift
struct TabContainer: View {
    @ObservedObject var catalogService: CatalogService
    @ObservedObject var recentStore: RecentGamesStore
    @ObservedObject var favoritesStore: FavoritesStore
    let onLogsRequest: () -> Void  // legacy passthrough; per-tab logs use NavigationStack value=.logs
    let onGameOpen: (Game) -> Void
    let onLoginClick: () -> Void

    @StateObject private var homeVM: HomeViewModel
    @StateObject private var browseVM: BrowseViewModel
    @State private var selected: String = "home"
    @State private var browseFilter: String? = nil

    init(catalogService: CatalogService, recentStore: RecentGamesStore, favoritesStore: FavoritesStore, onLogsRequest: @escaping () -> Void, onGameOpen: @escaping (Game) -> Void, onLoginClick: @escaping () -> Void) {
        self.catalogService = catalogService
        self.recentStore = recentStore
        self.favoritesStore = favoritesStore
        self.onLogsRequest = onLogsRequest
        self.onGameOpen = onGameOpen
        self.onLoginClick = onLoginClick
        _homeVM = StateObject(wrappedValue: HomeViewModel(service: catalogService, recents: recentStore, favorites: favoritesStore))
        _browseVM = StateObject(wrappedValue: BrowseViewModel(service: catalogService))
    }

    var body: some View {
        ZStack {
            TabView(selection: $selected) {
                NavigationStack { homeRoot }.tag("home")
                NavigationStack { browseRoot }.tag("browse")
                NavigationStack { favoritesRoot }.tag("favorites")
                NavigationStack { profileRoot }.tag("profile")
            }
            .tabViewStyle(.tabBarOnly_iOS18Plus_or_keepDefault) // see comment below
            VStack { Spacer(); FloatingTabBar(tabs: tabs, selectedKey: selected, onSelect: { selected = $0 }) }
        }
    }

    private var homeRoot: some View {
        HomeView(
            viewModel: homeVM,
            onGameClick: { g in onGameOpen(g) },
            onOpenBrowse: { selected = "browse" },
            onOpenBrowseFiltered: { genre in browseFilter = genre; selected = "browse" },
            onProfileClick: { selected = "profile" },
            onShareGame: { _ in /* share sheet via UIActivityVC */ }
        )
    }

    private var browseRoot: some View {
        BrowseView(viewModel: browseVM, profile: catalogService.profile, initialGenre: browseFilter, onGameClick: onGameOpen, onProfileClick: { selected = "profile" })
    }

    private var favoritesRoot: some View {
        FavoritesView(favorites: favoritesStore, onGameClick: onGameOpen, onBrowse: { selected = "browse" })
    }

    private var profileRoot: some View {
        ProfileView(service: catalogService, onLoginClick: onLoginClick, onLogsClick: onLogsRequest, onAboutClick: { /* push About via NavigationLink */ })
    }
}
```

Замечание про tab-bar:
- Стандартный `TabView` рисует системный bar; мы используем `FloatingTabBar` поверх и хотим скрыть системный. На iOS 16+ — `.toolbar(.hidden, for: .tabBar)` (на корне каждого tab content). Реализуем через `.toolbar(.hidden, for: .tabBar)` модификатор на `homeRoot`/`browseRoot`/etc.
- Скрытие FloatingTabBar при push: используем `@State private var hideBar` или, проще, `NavigationStack.path` count. Альтернатива — добавить `.toolbar(.hidden, for: .tabBar)` на каждом push-screen + локально завернуть `FloatingTabBar` в `.opacity(homeRoot has pushed ? 0 : 1)`. Минимально-инвазивно: каждый push-экран (`Game`, `Auth`, `Logs`, `About`) вешает `.preference(key: HideTabBarKey.self, value: true)`, контейнер читает и скрывает bar.

**Implementation hint:** ввести `PreferenceKey HideFloatingTabBarKey: Bool = false`, push-экраны (`GameView`, `AuthView`, `LogsView`, `AboutView`) делают `.preference(key: HideFloatingTabBarKey.self, value: true)` на root. Контейнер: `.onPreferenceChange(HideFloatingTabBarKey.self) { hideBar = $0 }`.

- [ ] Build
- [ ] Commit: `feat(ios): TabContainer with NavigationStack per tab`

### Task 26: iOS — `UGamesApp` wiring

**Files:**
- Modify: `ios/UGames/UGamesApp.swift`

Удаляем `case .catalog: TabContainer(hideBar: false) { CatalogView(...) }`. Заменяем на `TabContainer(catalogService:..., onGameOpen: { game in recentStore.record(game); route = .game(...) }, onLogsRequest: { route = .logs }, onLoginClick: { route = .auth })`. Deep-link уходит в `.game(appId:title:)`-route как и сейчас.

`onGameOpen` подменяется per-platform: на iOS делаем `route = .game(...)` глобально (как сейчас); per-tab push осмыслен только если `Game` живёт внутри стэка таба. Минимально-достаточно для Phase 2: оставить глобальный route на Game, как сейчас (полное per-tab push-stack-расщепление Game/Auth/Logs — необязательно для Phase 2; spec только требует «Bottom-tab-bar скрывается на GameDetail и GameScreen» — это уже делает `route` switch на корне). Per-tab back-stack для GameDetail — задача Phase 3.

Решение: **в Phase 2 сохраняем глобальные `route = .game / .auth / .logs / .about` на корне `RootView`**, TabContainer работает с per-tab Home/Browse/Favorites/Profile навигацией без push. About — push через `NavigationStack` value=`.about` внутри Profile-таба (полностью per-tab). Это минимизирует риск регрессии Game-flow и оставляет per-tab push для Phase 3.

- [ ] Build + ручной запуск, golden path как для Android.
- [ ] Commit: `feat(ios): wire 4-tab nav with HomeViewModel + BrowseViewModel`

### Task 27: iOS — Удалить `CatalogView.swift`

**Files:**
- Delete: `ios/UGames/Views/CatalogView.swift`

Включая private `ProfileSheet` внутри. Никаких ссылок не должно остаться (Task 26 уже разорвал).

- [ ] Build
- [ ] Commit: `chore(ios): remove old CatalogView + ProfileSheet`

---

### Task 28: финальный push + PR

- [ ] `git push -u origin feat/ui-redesign-phase-2`
- [ ] `gh pr create --title "UI redesign — Phase 2: Home/Browse/Favorites/Profile split"`. Описание ссылается на спеку и Phase-1 PR.
- [ ] Визуально проверить оба приложения: golden path + edge cases (offline, empty recents/favorites).

---

## Self-review

- **Spec coverage:** Hero / Continue / Favorites / Spotlight / Genre rows / Browse search+chips / FavoritesScreen+EmptyState / ProfileScreen+AboutScreen / 4-tab nav / удаление старого Catalog* — все есть в задачах 5-15 (Android) и 18-27 (iOS). GameDetail / in-game overlay / accessibility — out of scope.
- **Type consistency:** `HomeUiState`/`SpotlightBlock`/`GenreRow` именуются одинаково в плане; `FeedWithBlocks` — оба полей одинаковы; `FeedBlock.title/type/size/items` — одинаковы.
- **Open question 2 (categoryIDs query-param):** Phase 2 идёт client-side фильтром (как разрешено спекой). Network-side фильтрация — отдельная задача Phase 5 polish, не в этой фазе.
- **Open question 5 (mainColor iOS):** уже решено в Phase 1 (`Color(hex:)` есть в `Theme/Hex.swift`).

## Execution

Executes inline в текущей сессии (auto mode) — пользователь явно попросил приступить. Sub-skill: `superpowers:executing-plans`. Checkpoints — естественные, на каждом крупном куске (после Android-back-end, после Android-UI, после Android-wiring, после iOS-back-end, после iOS-UI, после iOS-wiring).
