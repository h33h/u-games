# U-Games Redesign — Phase 3: Game Detail

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal.** Inject a `GameDetail` push between the catalog list and the WebView, so a tap on any game card shows a hero + stats + “More like this” first; the user explicitly hits **Play now** to launch the WebView. Wires the `similar_games` endpoint (already implemented in `CatalogApi.similar` / `CatalogService.fetchSimilar`) into a horizontal row, plus a system Share sheet on the detail top-bar.

**Architecture.** Android (Kotlin/Compose) + iOS (Swift/SwiftUI). The big structural change is upgrading the per-tab navigation from a **single push slot** to a **push stack**, so `Tab → Detail → Game → Back → Detail → Back → Tab` works without losing the Detail context.

**Tech stack:** existing — no new dependencies.

**Spec:** [`../specs/2026-05-05-ui-ux-redesign-design.md`](../specs/2026-05-05-ui-ux-redesign-design.md) — section *Game Detail*.

**Out of scope this phase:** in-game overlay (Phase 4), accessibility (Phase 5), parallax-shrinking hero on scroll, video autoplay (Hero remains a static cover + mainColor halo until Phase 4 integrates ExoPlayer/AVPlayerLayer), `description`/`Year` fields (none guaranteed by the feed schema).

---

## Conventions

- One commit per task. `assembleDebug` / `xcodebuild build` green at the end of each Android- or iOS-section task that changes compilation surface.
- Cards / chips / state widgets re-use Phase 1/2 components verbatim — no new visual primitives. New screen-only widgets live next to `GameDetailScreen` / `GameDetailView`.
- Tokens: `UGColors`/`UGType` (Android), `UGColor`/`UGFont` (iOS). No raw hex.
- Skip the Hero video autoplay; static cover + mainColor halo is fine for Phase 3.

---

## File structure (after the phase)

### Android — new

| Path | What |
|---|---|
| `…/ui/detail/GameDetailUiState.kt` | data class state |
| `…/ui/detail/GameDetailViewModel.kt` | loads similar games, exposes state |
| `…/ui/detail/GameDetailScreen.kt` | hero + title block + stats + similar row + sticky CTA |

### Android — modified

| Path | What |
|---|---|
| `…/ui/TabContainer.kt` | per-tab `List<TabPushed>` stack (was single slot) |
| `…/ui/TabContainer.kt` | new `TabPushed.GameDetail(game: Game)` route |
| `…/MainActivity.kt` | card click pushes Detail; Detail.onPlay pushes Game; Detail.onShare reuses share intent; deep-link bypasses Detail and pushes Game directly |

### iOS — new

| Path | What |
|---|---|
| `…/ViewModels/GameDetailViewModel.swift` | `@MainActor` ObservableObject |
| `…/Views/GameDetailView.swift` | hero + title block + stats + similar row + sticky CTA |

### iOS — modified

| Path | What |
|---|---|
| `…/UGamesApp.swift` | `route` ⇒ `routeStack: [Route]`; `currentRoute` is `routeStack.last`. New `.gameDetail(Game)`. |
| `…/Views/TabContainer.swift` | onGameOpen pushes `.gameDetail(game)`; share sheet wired via `UIActivityViewController` from Detail |

---

## Navigation model — push stack

### Android

`TabContainer` currently stores `var homePushed: TabPushed` (and per-other-tab). Phase 3 changes each to `var homeStack: List<TabPushed>` (default empty), with:

- `push(route: TabPushed)` → `stack = stack + route`
- `pop()` → `stack = stack.dropLast(1)` (when empty, the bar comes back)
- `replace(route)` → `stack = stack.dropLast(1) + route`
- `topOfStack` (replaces the previous `activePushed`) = `stack.lastOrNull()`

`pushedHost(pushed, onPop, replace)` API stays the same — the host always renders the top of the stack.

`TabPushed` gains a `GameDetail(val game: Game)` variant.

### iOS

`RootView` currently stores `@State private var route: Route`. Phase 3 makes it `@State private var routeStack: [Route] = []`, with `currentRoute: Route` = `routeStack.last ?? .catalog`. Three helpers: `push(_:)`, `pop()`, `replaceTop(_:)`.

`Route` gains `case gameDetail(Game)`. Deep-link still resets to `[.game(...)]`.

---

## Detail screen layout (both platforms, mirror)

```
ScrollView {
  [hero 360h, top-padded for safe-area]
    full-bleed AsyncImage(coverUrl) + linear gradient (transparent → #000)
    sticky top row: ← / ♥ / ↗ glass-circle icons
  Title block (eyebrow + Display-XL + stat-chips)
  Stats grid (3 cards: Genre, Rating, Ratings)   // Year omitted (not in feed)
  More like this (LazyRow of TileGameCard, 12 max)  // skipped if empty/error
}
sticky bottom CTA (▶ Play now) — gradient, pulses 3 times
```

Cards in “More like this” are `TileGameCard` (Android) / `TileGameCard` (iOS) — same as Browse.

Share opens the system sheet with `playUrl` + title.

---

## Tasks

### Task 1 — Android: TabContainer per-tab push stack

**Files:** modify `android/app/src/main/kotlin/games/yandex/wrap/ui/TabContainer.kt`

- Add `data class GameDetail(val game: Game) : TabPushed` (so the screen renders synchronously without a fetch-by-id round trip).
- Replace each `var <tab>Pushed: TabPushed` with `var <tab>Stack: List<TabPushed>`.
- Compute `activePushed` as `currentStack.lastOrNull() ?: TabPushed.None`.
- `push(r)` appends; `onPop` drops last; `replace(r)` swaps the top.
- `initialPushed` semantics: if not `None`, the active tab seeds with `listOf(initialPushed)` instead of empty.

- [ ] Build: `cd android && ./gradlew :app:compileDebugKotlin`
- [ ] Commit: `feat(android): TabContainer with per-tab push stack + GameDetail route`

### Task 2 — Android: `GameDetailUiState`

**Files:** create `android/app/src/main/kotlin/games/yandex/wrap/ui/detail/GameDetailUiState.kt`

```kotlin
data class GameDetailUiState(
    val game: Game,
    val isFavorite: Boolean = false,
    val similar: List<Game> = emptyList(),
    val isLoadingSimilar: Boolean = false,
    val similarError: String? = null,
)
```

- [ ] Build
- [ ] Commit: `feat(android): add GameDetailUiState`

### Task 3 — Android: `GameDetailViewModel`

**Files:** create `android/app/src/main/kotlin/games/yandex/wrap/ui/detail/GameDetailViewModel.kt`

Constructor: `(repository: CatalogRepository, initialGame: Game)`.

- Exposes `state: StateFlow<GameDetailUiState>`.
- On `init { loadSimilar() }` — calls `repository.similar(game.appId)`.
- Observes `repository.favoriteIds()` to update `isFavorite`.
- `toggleFavorite()` → `repository.toggleFavorite(game)`.

- [ ] Build
- [ ] Commit: `feat(android): add GameDetailViewModel`

### Task 4 — Android: `GameDetailScreen`

**Files:** create `android/app/src/main/kotlin/games/yandex/wrap/ui/detail/GameDetailScreen.kt`

Composable signature:

```kotlin
@Composable
fun GameDetailScreen(
    viewModel: GameDetailViewModel,
    onBack: () -> Unit,
    onPlay: (Game) -> Unit,
    onShare: (Game) -> Unit,
    onSimilarClick: (Game) -> Unit,
)
```

Layout (`Column` over a `Box` so the sticky CTA can layer above):

1. **`LazyColumn`** with status-bar inset (top), 110dp bottom inset (sticky CTA + tab-bar safe).
2. **Hero** (360dp): same recipe as `HeroSection` minus FEATURED/CTA — full-bleed AsyncImage, vertical gradient overlay, halo by `mainColor`. Sticky top row: `←`, `♥` (filled when `isFavorite`), `↗`.
3. **Title block**: eyebrow `${categories[0]?.uppercase()} · GAME` (skip eyebrow if no category). `Text(game.title, UGType.DisplayXL)`. Stat-chips row (Rating, RatingCount, “No ads” yellow-tint).
4. **Stats grid**: 3 cards, equal-weight `Row`, surface bg, 14dp radius. Each card: tiny eyebrow + value. Cards: Genre / Rating / Ratings.
5. **More like this**: section header (`UGType.TitleM`). If `isLoadingSimilar` → 3 skeleton tiles (140dp wide). If `similar.isNotEmpty()` → `LazyRow` of `TileGameCard` 160dp wide each. If empty + not loading → section hidden.
6. Spacer 16.

Sticky CTA:
- `Box(Modifier.align(Alignment.BottomCenter))` — gradient `▶ Play now` button + fade-mask `transparent→#000`. Apply `pulse` modifier (3 impulses, scale 1.0 → 1.04, 2400ms ease-in-out).

- [ ] Build + Compose preview
- [ ] Commit: `feat(android): add GameDetailScreen with hero + stats + similar + sticky CTA`

### Task 5 — Android: wire `MainActivity` for Detail push

**Files:** modify `android/app/src/main/kotlin/games/yandex/wrap/MainActivity.kt`

- `openGame` callback: `push(TabPushed.GameDetail(game))` (was `TabPushed.Game(...)`).
- `pushedHost`:
  - new `is TabPushed.GameDetail` branch — instantiates a fresh `GameDetailViewModel(repository, pushed.game)`, hooks `onPlay = { game -> push(TabPushed.Game(game.appId, game.title)) }`, `onShare = openShare`, `onSimilarClick = { g -> push(TabPushed.GameDetail(g)) }`, `onBack = onPop`. (`push` here is the per-tab push; we accept it as part of the host signature change — see below.)
- Adjust `pushedHost` callback signature from `(pushed, onPop, replace) -> Unit` to `(pushed, push, onPop, replace) -> Unit` so Detail can stack Game on top.
- Deep-link: still seeds `TabPushed.Game(appId, title="")` directly (skips Detail because we don't have the Game object on cold start).

- [ ] Build + manual run: golden path Home → tap card → Detail → Play → Game → Back → Detail → Back → Home; deep-link `ugames://app/123` opens straight into Game; from Detail, tap a Similar tile → Detail of that game pushes; share sheet opens.
- [ ] Commit: `feat(android): wire GameDetail push between catalog and WebView`

### Task 6 — Android build verify

- [ ] `cd android && ./gradlew :app:assembleDebug` green.

---

### Task 7 — iOS: `RootView` route stack

**Files:** modify `ios/UGames/UGamesApp.swift`

- `Route` gains `case gameDetail(Game)`.
- `@State private var route: Route = .catalog` ⇒ `@State private var routeStack: [Route] = []`.
- Helpers: `push(_:)`, `pop()`, `replaceTop(_:)`, `reset(to:)`.
- `currentRoute: Route { routeStack.last ?? .catalog }`.
- Update three callsites: `onGameOpen` ⇒ push `.gameDetail(game)`; `onLogsRequest` ⇒ push `.logs`; `onLoginClick` ⇒ push `.auth`.
- `onOpenURL` ⇒ `reset(to: .game(appId, title: ""))`.
- AuthView/LogsView/GameView/GameDetailView `onClose`/`onBack` callbacks call `pop()`.

- [ ] Commit: `feat(ios): RootView routeStack for nested push (Detail → Game)`

### Task 8 — iOS: `GameDetailViewModel` + `GameDetailView`

**Files:** create `ios/UGames/ViewModels/GameDetailViewModel.swift` and `ios/UGames/Views/GameDetailView.swift`.

ViewModel:

```swift
@MainActor
final class GameDetailViewModel: ObservableObject {
    @Published private(set) var game: Game
    @Published private(set) var similar: [Game] = []
    @Published private(set) var isLoadingSimilar: Bool = false
    @Published private(set) var similarError: String?
    private let service: CatalogService
    init(game: Game, service: CatalogService) { … ; Task { await loadSimilar() } }
    func loadSimilar() async { … service.fetchSimilar(appId:) … }
}
```

View signature:

```swift
struct GameDetailView: View {
    @ObservedObject var viewModel: GameDetailViewModel
    @ObservedObject var favorites: FavoritesStore
    let onBack: () -> Void
    let onPlay: (Game) -> Void
    let onShare: (Game) -> Void
    let onSimilarClick: (Game) -> Void
    var body: some View { … }
}
```

Mirror the Android layout — same sections in same order. Use `TileGameCard` for similar tiles. Pulse the CTA via `withAnimation(.easeInOut.repeatCount(3, autoreverses: true))` on `.scaleEffect(1.04)` triggered by an `@State` flag set in `.onAppear`.

- [ ] Build
- [ ] Commit: `feat(ios): add GameDetailViewModel + GameDetailView`

### Task 9 — iOS: wire TabContainer/RootView for Detail push

**Files:** modify `ios/UGames/Views/TabContainer.swift` and finalize wiring in `ios/UGames/UGamesApp.swift`.

- TabContainer's `onGameOpen` already accepts `(Game) -> Void` — RootView changes it to `push(.gameDetail(game))`. No change inside TabContainer.
- RootView render switch: add `.gameDetail(game)` branch — wraps a fresh `GameDetailViewModel(game:, service:)` in a child view; `onPlay` ⇒ `push(.game(appId, title))`; `onSimilarClick` ⇒ `push(.gameDetail(g))`; `onShare` ⇒ presents a `UIActivityViewController` via a UIKit bridge (small `ShareSheet` wrapper) hooked to `playUrl` + `title`; `onBack` ⇒ `pop()`.
- Profile sheet's `onShareGame: { _ in /* phase 3 */ }` already exists — leave; Home doesn't drive a share-from-card flow yet (only Detail does).

- [ ] Commit: `feat(ios): wire GameDetail push + share sheet`

### Task 10 — iOS build verify

- [ ] `cd ios && xcodebuild -project UGames.xcodeproj -scheme UGames -sdk iphonesimulator -configuration Debug build` green.

---

### Task 11 — Push + PR

- [ ] `git push -u origin feat/ui-redesign-phase-3`
- [ ] `gh pr create --title "UI redesign — Phase 3: GameDetail screen"` with link back to spec + Phase 2 PR.

---

## Self-review

- **Spec coverage.** Hero / Title block / Stats grid / More-like-this / sticky CTA / Share — covered. About body skipped (no field in feed). Year omitted (no field). Video autoplay deferred to Phase 4 (along with overlay).
- **Stack semantics.** Going through Detail twice (`Detail(A) → Similar tile → Detail(B)`) stacks two screens; Back unwinds them one at a time. Going `Detail → Play → Back` returns to Detail (not the catalog), which matches the spec’s “GameDetail and GameScreen дублируются в каждом стеке”.
- **Deep-link.** Stays a one-shot `.game(...)` push — bypasses Detail because we don't have the `Game` object on cold start.
- **Risk.** Stack-list refactor in TabContainer is the highest-risk piece; the existing tests are visual, so we verify by manually walking the golden path before committing.
