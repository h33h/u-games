# U-Games — UI/UX редизайн (premium / editorial)

**Date:** 2026-05-05
**Status:** approved (v2 направление)
**Scope:** Android (Kotlin/Compose) + iOS (Swift/SwiftUI). Без изменений back-end / ad-blocking / WebView-инжекции.

## Цели

Поднять каталог обёртки до качества premium mobile gaming-приложения (App Store Today / Apple Arcade tier) при сохранении:

- единственного источника данных — Yandex `catalogue/v2/feed/` и `similar_games/`,
- ad-blocking-цепочки (`shared/inject/*`, `AdBlockingClient`, `WKContentRuleList`),
- структуры Room/CoreData (`favorites`, `recents`),
- авторизационного потока (`passport.yandex.ru` OAuth).

Боли пользователя, которые лечим:

- A. Каталог плоский и одинаковый — нет визуального ритма, нет жанров.
- B. Поиск/навигация неудобные — фильтров нет, всё в одной сетке.
- C. Нет деталь-страницы игры — клик сразу запускает WebView.
- D. Экран игры спартанский — нет кнопки выхода/перезапуска/индикатора загрузки.

Auth/Profile/Logs (E) — только косметика по новой палитре, структуру не трогаем.

## Принципы

- **Одна задача — один таб.** Bottom-tabs Home / Browse / Favorites / Profile.
- **Editorial home.** Hero + кураторские ряды, не сетка-мешок.
- **Push-навигация для деталей.** Клик по карточке → `GameDetail` push, не сразу WebView. `Play` на детали запускает WebView.
- **Premium через глубину, не через объём.** Слои фона (mesh + noise + grain), color halo по `mainColor`, glass-blur, sparkle-бейджи, дисплейная типографика.
- **Честные данные.** Не выдумываем «Plays today / 12K» — Yandex feed их не отдаёт. Используем только то, что есть: `ratingCount`, `categoriesNames`, `lastPlayedTS` (для Recently), `media.videos`, `media.cover.mainColor`.
- **Skeleton-лоадеры везде**, где раньше был `CircularProgressIndicator`.
- **Empty / Error states** — единый компонент с иконкой, текстом, CTA, не голый текст.

## Информационная архитектура

```
TabContainer (bottom tabs, floating glass)
├── Home (push-stack)
│   ├── HomeScreen           — Hero + rows
│   ├── GameDetailScreen     — push
│   └── GameScreen           — push поверх Detail
├── Browse (push-stack)
│   ├── BrowseScreen         — chips + grid + search
│   ├── GameDetailScreen
│   └── GameScreen
├── Favorites (push-stack)
│   ├── FavoritesScreen
│   ├── GameDetailScreen
│   └── GameScreen
└── Profile (push-stack)
    ├── ProfileScreen
    ├── AuthScreen           — push
    └── LogsScreen           — push
```

`GameDetailScreen` и `GameScreen` дублируются в каждом стеке (стандартная мобильная практика, чтобы кнопка «Назад» возвращала в исходный таб). Bottom-tab-bar скрывается на `GameDetail` и `GameScreen`.

## Визуальная система

### Цветовые токены

| Token | Значение | Использование |
|---|---|---|
| `bg.0` | `#000000` | Корневой фон |
| `bg.mesh` | mesh из `rgba(65,180,246,.18) → rgba(155,108,255,.14) → rgba(255,199,0,.08) → #000` | Бэкграунд Home/Browse |
| `surface` | `#0D0D10` | Search-input, инфо-карточки |
| `elevated` | `#1A1A20` | Bottom-sheet, модалки, аватар-вью |
| `divider` | `#1F1F22` | Линии-разделители |
| `text.primary` | `#FFFFFF` | Заголовки |
| `text.secondary` | `#C8C8D0` | Body |
| `text.muted` | `#7A7A82` | Caption, eyebrow |
| `accent` | `#FFC700` | Активный таб, ★rating, accent text |
| `accent.gradient` | `135deg, #FFC700 → #FF7E00` | CTA-кнопки, аватар-ring |
| `danger` | `#FF4D6A` | Сильно негативное состояние, sign-out |
| `cover.mainColor` | per-game из `media.cover.mainColor` | Halo-glow, placeholder, dynamic accent на Detail |
| `glass` | `rgba(13,13,16,0.55) + blur(28px)` | Hero-overlay-кнопки, tab-bar (API ≥ 31; fallback `rgba(20,20,24,0.85)`) |

### Типографика (system font: SF iOS / Roboto Android)

| Стиль | Размер / Вес / Tracking | Использование |
|---|---|---|
| Display | 30 / 900 / -0.8px | Hero title, Detail title (часть слов в `cover.mainColor`) |
| Title-L | 24 / 800 / -0.5px | Greeting Home (`Good evening`), Detail eyebrow-следующий |
| Title-M | 18 / 800 / -0.3px | Заголовки рядов («Trending now») |
| Body | 15 / 400 | Описание игры |
| Body-S | 13 / 500 | Карточка title, мета |
| Label | 11 / 600 / 1.2px / UPPERCASE | Eyebrow («Tuesday · Top picks»), bag-лейблы |
| Caption | 10 / 700 | Stat-chips, badges |

### Радиусы / spacing / motion

- Радиусы: 10 (chip) · 14 (button/input) · 16 (card) · 18 (Hero/CTA) · 22 (story-card) · 28 (tab-bar pill).
- Spacing: 4 / 8 / 12 / 16 / 20 / 24.
- Motion: 240ms `cubic-bezier(0.2, 0.0, 0.0, 1.0)` для push, 200ms fade для overlay, spring(stiffness=300, damping=24) для tab-индикатора, 2400ms ease-in-out pulse на главной CTA Detail (затухает после 3 импульсов = 7.2s).

### Эффекты

- **Color halo** на карточках: `box-shadow: 0 12px 30px {mainColor}40, 0 0 0 1px {mainColor}30 inset`. На Compose — `Modifier.drawBehind { drawShadow(...) }` или `Surface(shadowElevation = 12.dp, tonalElevation = 0.dp)` + `border` с alpha. На SwiftUI — `.shadow(color: mainColor.opacity(0.35), radius: 14, y: 12)` + `.overlay(RoundedRectangle().stroke(mainColor.opacity(0.2)))`.
- **Grain noise** через 2-pixel radial-pattern с `mix-blend-mode: overlay` на iOS (CIFilter), Compose (`Modifier.drawWithCache` + tiled `Brush.linearGradient` хак или PNG из shared/assets). Если технически дорого — **опускаем grain в первой итерации**, оставляем только halo+gradient (это бóльшая часть premium-впечатления).
- **Glass blur**: iOS 16+ — `.background(.ultraThinMaterial)`. Android API ≥ 31 — `RenderEffect.createBlurEffect(28f, 28f, Shader.TileMode.CLAMP)` через `Modifier.graphicsLayer { renderEffect = ... }`. Android API < 31 — fallback semi-transparent surface.
- **Pulse**: SwiftUI `.scaleEffect()` + `.shadow()` в `withAnimation(.easeInOut.repeatCount(3, autoreverses: true))`. Compose — `rememberInfiniteTransition` с `repeatMode = RepeatMode.Reverse, iterations = 3`.

## Экраны — детали

### Home

`LazyColumn` / `ScrollView` с верхним padding под status-bar и нижним под floating tab-bar (62 + 14 = 76dp).

1. **Header** — eyebrow «{День · Top picks}» (день из системной даты), greeting «Good evening 👋» (из часа: morning < 12, afternoon < 18, evening). Справа — аватар 38dp с gradient-ring (если авторизован) или generic icon.
2. **Search-stub** — псевдо-input «🔍 Search games», тап → `Browse` с автофокусом TextField. Это снимает дубль-поиск с topbar.
3. **Hero** — высота 300dp, `LazyColumn-item` full-width минус 14dp. Источник: первый item первого `categorized` блока feed-а с `size: "l"` (фолбэк — первая игра feed-а с самым высоким `ratingCount`). Стабильный по сессии.
   - Бэкграунд: если `media.videos[0]` есть — autoplay muted-loop `mp4StreamUrl` (Android `androidx.media3:media3-exoplayer` 1.4+; iOS `AVPlayerLayer`). Если нет — `cover` + `mainColor` радиальный градиент.
   - Поверх: vignette `linear-gradient(180deg, transparent 35%, rgba(0,0,0,.85) 100%)`.
   - Top-row: `✦ Featured today` sparkle-бейдж + glass-кнопки `♥` `↗`.
   - LIVE preview pill (показывается только если есть видео).
   - Stat-chips: `★ {rating}`, `{ratingCount} ratings`, `{categoriesNames[0]}`. Без выдуманных «12K plays today».
   - Display-title 30/900, последнее слово в `cover.mainColor`.
   - CTA: `▶ Play now` (gradient pulse 3 импульса) + glass `Save`. На клик `Play now` → `GameDetail` push (не WebView). Сохранилось требование «Detail before WebView».
4. **Continue playing** — `recent` (table из Room/CoreData), wide-карточки 140×96. Бейдж «Last played Xh ago». Скрыт если recent пуст.
5. **Your favorites** — wide-карточки. Скрыт если пусто.
6. **Spotlight** (story-card) — синтетический ряд: берём первый `categorized` блок feed-а с `size: "s"` и `len(items) ≥ 5`, рендерим его как editorial story-card 22-радиус, 160dp, 3 наложенные обложки справа с tilt. Eyebrow «Spotlight · {block.title}». Тап → Browse pre-filtered по этому жанру. Если такого блока нет — секция скрыта.
7. **Per-genre rows** — для каждого `categorized` блока feed-а (size любой), кроме уже использованного в Spotlight, рендерим заголовок + горизонтальную ленту square-карточек 130×130 + title под ней. «See all →» → Browse с предфильтром.
8. **Loader** — после последнего ряда, если `hasMore`, показываем 1 ряд из 3-х `Skeleton` карточек. `loadMore` срабатывает на appearance последнего реального ряда (не grid, как сейчас).

### Browse

- Sticky topbar: `OutlinedTextField` (search) + аватар. Не переиспользуем `Home`-header.
- Sticky chips-row под topbar: `All` (default) + `siteNavigationLinks.categories[]` из feed-ответа. Активный чип — `accent` фон, `text.primary` текст, glow `0 0 14px {accent}40`.
- Сетка `LazyVerticalGrid` / `LazyVGrid` с `Adaptive(160dp)`, новый `GameCard.Tile` (см. секцию Cards).
- Чип `All` показывает feed как сейчас, paginated. Жанровый чип — клиентский фильтр по `categoriesNames` из уже загруженных страниц. Если требуется свежий список — оставляем feed загружаться до `hasMore=false` под капотом (на этапе implement проверим, как ведёт себя `categoryIDs` query-param на endpoint-е; если работает — переключаемся на сетевой запрос для жанра).
- Submit поиска переключает в `Mode.Search`, чипы скрываются.

### Favorites

- Если пусто: `EmptyState(icon: heart, title: "No favorites yet", body: "Tap ♥ on any game to save it", cta: "Browse games", onCta: → Browse tab)`.
- Иначе: header «Favorites · {N}» + grid из `Tile`-карточек.

### Profile

Заменяет `ProfileSheet` (старый код удаляется).

- Hero-секция: 96dp avatar, `accent.gradient` ring если `hasYaPlus`. Под ним — display-name и login (если отличается).
- Yandex Plus pill (`accent`-tint).
- Список «Settings» — `elevated` карточки с разделителями:
  - Sign in / Sign out (зависит от состояния, danger-цвет на Sign out).
  - Diagnostic logs → push `LogsScreen`.
  - About → push `AboutScreen` (новый, минимальный: версия + ссылка на GitHub-репо).
- Long-press на аватаре оставляем как backup-вход в Logs (для debug-привычки).

### Game Detail

`ScrollView` с прозрачным sticky-низом.

1. **Hero 360dp** — те же правила что Home Hero (видео или градиент по `mainColor`). Sticky-меньше: на скролле hero уходит за безопасную зону, размер 360→160dp с parallax-fade. Top-кнопки `← / ♥ / ↗` остаются sticky на topbar (glass).
2. **Title block** — eyebrow «{categoriesNames[0]} · {year}» (year хардкодим текущим, если в feed нет). Display-34/900, последнее слово в `cover.mainColor`. Stat-chips: `★ {rating}`, `{ratingCount} ratings`, `No ads` (yellow-tint).
3. **About** — eyebrow `ABOUT`, body. Поле описания **проверяем на этапе implement**: в `feed-schema.md` `description` не задокументирован. Если в живом ответе нет — секция скрывается.
4. **Stats grid** (3 колонки, `surface`-карточки 14r):
   - `Genre` — `categoriesNames[0]` capitalized.
   - `Rating` — `★ {rating}` + `{ratingCount} ratings` мелким.
   - `Year` — текущий год (или `feed.shareImage` URL-парсинг, если содержит дату; на этапе implement).
   - **Не используем «Plays / Avg session» — нет в API.**
5. **More like this** — `LazyRow` из `getSimilarGames(appId)` по endpoint `/api/catalogue/v2/similar_games/?app_id={id}&games_count=12`. Tile-карточки. Тап → push новой Detail-страницы (рекурсия allowed).
6. **Sticky CTA bar** (15dp от низа): gradient `▶ Play now` или (если в `recent`) `Continue playing` + sub-line «Last played {N}h ago». Pulse 3 импульса при появлении. Над ним — fade-mask `linear-gradient(180deg, transparent, #000 30%)`.
7. **Share** через `↗` — системный share sheet с `https://yandex.com/games/app/{appId}` и `game.title`.

### Game Screen (WebView)

- WebView без изменений в логике инжекции (`shared/inject/*`, `AdBlockingClient`, `WKContentRuleList`).
- **Top-overlay скрыт по умолчанию.** Жест: tap в верхние 80dp экрана = показать на 2.5s, ещё tap = скрыть. После показа auto-fade 200ms.
- **Layout overlay**: glass card 14dp от верха, padding 10/12, скруглённая 18r, гориз. layout: `← Back · {title 1 line truncate · loading-state caption} · ↻ Restart · ♥ Favorite · ⋯ More`.
- **Loading progress bar**: 3dp полоска под overlay, gradient `accent → accent-orange`, `box-shadow: 0 0 12px {accent}`. Прогресс: `WebView.progressChanged` (Android) / `WKWebView.estimatedProgress` (iOS, KVO).
- **More-sheet**: bottom-sheet с `Share`, `Diagnostic logs`, `Open in browser` (запускает intent / `UIApplication.shared.open`).
- **Rotation overlay** (iOS уже есть) — переоформить под новую палитру; Android — вынести аналог (`OrientationOverlayView`).

## Карточки игр

3 типа, в едином файле `Components/GameCard.kt` / `GameCard.swift`:

### Tile (Browse, Favorites, Similar grid)

- `Adaptive(160dp)`, `aspect-ratio 16/10` cover, `mainColor` фолбэк до загрузки.
- Внутри cover: top-right heart toggle 30dp glass-circle, bottom-left rating pill (`★ {rating}` accent text on dark glass).
- Под cover: title (Body-S 13/500, max 1 line), мета `{genre} · {ratingCount} ratings` (Caption 10/600 muted).
- Halo по `mainColor`.

### Wide (Continue, Trending row, Favorites row на Home)

- 140×96dp, cover full-bleed.
- Bottom-left: title 11/700 с `text-shadow`.
- Top-right: progress badge — **только** если есть `lastPlayedTS` (не выдуманное `62%`).
- Halo по `mainColor`.

### Square (Recently row если хочется компактнее, или per-genre rows)

- 130×130dp иконка с радиусом 16, под ней title 12/700 (1 line) и мета (10/600 muted).
- Halo по `mainColor`.

## Loading / Empty / Error

Единые компоненты в `Components/States.kt` / `States.swift`:

- `Skeleton` — анимированный shimmer `1A1A20 → 222228` через `infiniteTransition` (Compose) / `LinearGradient` маски (SwiftUI). Используется на Home для Hero (300dp скелетон с halo `accent`-tint), для row-headers, для tile/wide/square заглушек.
- `EmptyState(icon: ImageVector, title: String, body: String?, ctaLabel: String?, onCta: () -> Unit)` — иконка 48dp, title Title-M, body 13 muted, CTA — gradient-button.
- `ErrorState(message: String, onRetry: () -> Unit)` — стилизованный wrapper над текущим Retry-блоком.

## Технические изменения по файлам

### Android — новые файлы

- `ui/theme/UGamesTheme.kt` — палитра, типографика, обёртка `MaterialTheme`.
- `ui/theme/Color.kt`, `ui/theme/Type.kt` — токены.
- `ui/components/GameCard.kt` — Tile / Wide / Square варианты.
- `ui/components/Hero.kt` — Hero с видео/градиентом.
- `ui/components/StoryCard.kt` — Spotlight editorial card.
- `ui/components/Skeleton.kt`, `ui/components/EmptyState.kt`, `ui/components/ErrorState.kt`.
- `ui/components/GenreChipRow.kt`.
- `ui/components/FloatingTabBar.kt` — glass tab-bar (API 31+ blur, fallback semi-transparent).
- `ui/HomeScreen.kt` — новый.
- `ui/BrowseScreen.kt` — новый.
- `ui/FavoritesScreen.kt` — новый.
- `ui/ProfileScreen.kt` — новый (заменяет старый `ProfileSheet`).
- `ui/AboutScreen.kt` — новый минимальный.
- `ui/GameDetailScreen.kt` — новый.
- `ui/HomeViewModel.kt` — производит `HomeUiState { hero, continueRow, favoritesRow, spotlight, genreRows, hasMore, isLoading }`.
- `ui/BrowseViewModel.kt`, `ui/FavoritesViewModel.kt`, `ui/GameDetailViewModel.kt`.
- `webview/InGameOverlayController.kt` — auto-hide state + load progress.

### Android — изменяем

- `MainActivity.kt` — `Scaffold` + `NavigationBar` (4 таба) с внутренними `NavHost` на каждый таб.
- `catalog/CatalogApi.kt` — добавляем `suspend fun getSimilarGames(appId: Long, lang: String, count: Int = 12): List<Game>`.
- `catalog/Game.kt` — добавляем поле `mainColor: String?` (из `media.cover.mainColor`), `iconMainColor: String?`, `videoUrl: String?` (`media.videos[0].mp4StreamUrl`).
- `webview/GameWebView.kt` — pipe `progressChanged` в `InGameOverlayController`.
- `app/build.gradle.kts` — `androidx.media3:media3-exoplayer` + `androidx.media3:media3-ui` 1.4.1.

### Android — удаляем

- `ui/CatalogScreen.kt` — заменяется на Home/Browse/Favorites split.
- `ui/CatalogViewModel.kt` — кишки переезжают в Home/Browse/FavoritesViewModel; общий repo выносим если нужно.
- `ProfileSheet` (внутри `CatalogScreen.kt`) — удаляется вместе с файлом.

### iOS — новые файлы

- `Theme/Theme.swift` — `Color` / `Font` extensions.
- `Components/GameCard.swift` — Tile / Wide / Square.
- `Components/Hero.swift`.
- `Components/StoryCard.swift`.
- `Components/Skeleton.swift`, `Components/EmptyState.swift`, `Components/ErrorState.swift`.
- `Components/GenreChipRow.swift`.
- `Components/FloatingTabBar.swift`.
- `Views/HomeView.swift`, `Views/BrowseView.swift`, `Views/FavoritesView.swift`, `Views/ProfileView.swift`, `Views/AboutView.swift`, `Views/GameDetailView.swift`.
- `ViewModels/HomeViewModel.swift`, `ViewModels/BrowseViewModel.swift`, `ViewModels/FavoritesViewModel.swift`, `ViewModels/GameDetailViewModel.swift`.
- `WebView/InGameOverlayState.swift` — observable.

### iOS — изменяем

- `UGamesApp.swift` — `TabView` с 4 табами, каждый внутри `NavigationStack`. Тех. отдельные `@StateObject` для каждого таба (нет shared service над WebView).
- `Catalog/CatalogService.swift` — `func similarGames(appId: Int, lang: String) async throws -> [Game]`.
- `Catalog/Game.swift` — добавляем `mainColor`, `iconMainColor`, `videoUrl`.
- `WebView/GameWebView.swift` — KVO на `estimatedProgress`, прокидываем в `InGameOverlayState`.

### iOS — удаляем

- `Views/CatalogView.swift` — split.
- `ProfileSheet` внутри неё.

### Что НЕ трогаем

- `shared/inject/honest-path.js`, `shared/inject/ya-sdk-stub.js`, `shared/inject/pwa-mode.css`, `shared/inject/pwa-mode.js`.
- `shared/blocklist/ad-domains.txt`.
- `webview/AdBlockingClient.kt` логика, `WKContentRuleList` setup.
- `webview/PopupHandler.kt`, OAuth flow.
- Room schema (`AppDatabase`, `Favorite`, `Recent`).
- `Diagnostics/LogStore`, `Diagnostics/OrientationStore` — только UI-обёртки в новых стилях.
- CI workflows.

## Этапы реализации (для writing-plans)

**Phase 1 — Foundation (без видимых изменений)**
- Theme tokens, базовые компоненты (`GameCard.Tile/Wide/Square`, `Skeleton`, `EmptyState`, `ErrorState`, `Hero`-stub, `StoryCard`-stub).
- Bottom-tab Scaffold/TabView с одним табом «Home», который пока рендерит существующий `CatalogScreen` без изменений. CI зелёный.
- Расширить `Game` модель новыми полями (`mainColor`, `videoUrl`), парсинг в `CatalogApi` / `CatalogService`. media3 / AVPlayer добавлены в зависимости.

**Phase 2 — Home + Browse + Favorites + Profile split**
- `HomeScreen` (search-stub, Hero, rows, Spotlight). `HomeViewModel` производит `HomeUiState`.
- `BrowseScreen` с chips + grid + search.
- `FavoritesScreen` (grid + EmptyState).
- `ProfileScreen` (заменяет ProfileSheet) + `AboutScreen`.
- Удалить старый `CatalogScreen` / `CatalogView`.
- Bottom-tab нав получает 4 таба.

**Phase 3 — Game Detail**
- `GameDetailScreen` с Hero (video/градиент), stats grid, More-like-this, sticky CTA.
- `CatalogApi.getSimilarGames` / `CatalogService.similarGames`.
- Меняем поведение `onGameClick`: → push Detail (не сразу WebView). На Detail `Play` запускает WebView.
- Share через системный sheet.

**Phase 4 — In-game overlay + polish**
- `InGameOverlayController` / `InGameOverlayState` с auto-hide, load-progress.
- Переоформить Auth-screen и rotation-overlay под новую палитру.
- Long-press quick-actions sheet на карточках (Play / Add favorite / Share / Open detail).

**Phase 5 — Cleanup**
- Удалить мёртвый код (`ProfileSheet`, неиспользуемые цвета, дубли).
- Accessibility-проход: `contentDescription`, dynamic type, contrast >= 4.5.
- Ручное тестирование на реальном устройстве: golden path (запуск игры из Home Hero → Detail → Play → Back → Restart → Favorite → Back), edge cases (оффлайн / медленная сеть / пустые `recent`/`favorites`).
- Smoke-тесты state-классов (`HomeUiState`, `BrowseUiState`).

## Открытые вопросы (резолвим на implement)

1. **`description` в feed-ответе** — задокументирован пустым в schema. Проверяем на живом запросе; если есть — выводим, нет — секцию скрываем. Не блокер.
2. **`categoryIDs` query-param** — поддерживает ли endpoint фильтрацию по жанру? Проверяем; если да — Browse-чипы переключаются на сетевые запросы; если нет — клиентский фильтр.
3. **Год выхода** — нет в feed. Варианты: (a) скрываем поле в stats grid, (b) оставляем хардкод текущего, (c) парсим из `feed.shareImage` если он содержит timestamp. Решаем при impl, по умолчанию (a).
4. **Android API < 31 fallback** — semi-transparent surface вместо blur. Уже учтено в спеке, но визуально проверить на эмуляторе API 28-30.
5. **`mainColor` на iOS** — `Color(hex:)` extension нужно добавить (его сейчас нет; `feed-schema.md` отдаёт `#41B4F6`-стайл строки).
6. **Pulse-анимация** — после 3 импульсов вырубается; проверить что не съедает батарею при долгом show.

## Не-цели

- Никакого нового бэкенда / прокси / собственной БД на сервере.
- Никаких сторонних дизайн-либ (Material Components 3 уже есть, SwiftUI стандарт). Без Lottie, без Rive — анимации руками.
- Никаких purchases / монетизации / рекламы (это и так не цель проекта).
- Никаких изменений в ad-blocking / SDK-стабе.
- Никаких частиц/3D-tilt по гироскопу/post-processing на этой итерации (можно добавить позже отдельной спекой).
