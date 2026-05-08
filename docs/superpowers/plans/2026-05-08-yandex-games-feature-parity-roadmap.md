# План: что нужно реализовать в u-games iOS, чтобы покрыть удобный функционал yandex.games

## Контекст и продуктовая рамка

**Цель приложения** — быть «лучшим клиентом Yandex Games для iOS»: те же игры, но **без рекламы и со всеми покупками бесплатно**, плюс — догнать Yandex по всем фичам, которые делают пользование удобным.

Это означает чёткое разделение на **две корзины**:

1. **Догоняем UX и каталог** — всё, что помогает игроку находить, запускать, продолжать и сохранять игры.
2. **Сознательно не делаем** — всё, что обслуживает монетизационную модель Yandex (реклама, Plus-апселлы, реальная Yans-валюта, реальные IAP, рекламная аналитика). Эти поверхности должны быть либо вырезаны, либо подменены на «бесплатно/безлимитно».

Базовый аудит сделан: посмотрел iOS-код (`ios/UGames/`) и через chrome-devtools прошёлся по `yandex.com/games` (homepage, /categories, /tags, /all-games, /user, /app/{id}, /search, network, `__appData__`, авторизованная сессия).

---

## Что уже есть в iOS

- 4 таба: Home / Browse / Favorites / Profile
- Каталог через `/games/api/catalogue/v2/feed/`, `search/`, `similar_games/`
- WebView fullscreen с iOS Safari UA + ad-blocking content rules
- `ya-sdk-stub.js`: `adv.*` → auto-close, `purchase()` → fake free token, `screen.orientation.lock` ловится, логи через `ugamesLog`
- Yandex Passport SSO, cookies-bridge, локальные favorites
- Game detail: title, cover, rating, description, screenshots, genres, languages, age rating, similar
- Категории как chip-row, EN/RU автодетект, простая локализация

---

## Что НЕ делаем (явный non-goals список)

Перечисляю отдельно, чтобы не было соблазна реализовать «потому что есть у Yandex»:

| # | Фича Yandex | Почему пропускаем |
|---|---|---|
| N1 | Pre-roll fullscreen ad | Уже стабится в `ya-sdk-stub.js` — оставляем как есть |
| N2 | Rewarded video | Auto-grant в стабе — оставляем |
| N3 | In-feed `adv` блоки | Не рендерим в Home/Browse |
| N4 | Реальная IAP | Стаб возвращает `__yga_free_*` — оставляем |
| N5 | Yans wallet (баланс в header) | Не показываем UI вообще; в SDK подменим на «∞» если игра запрашивает |
| N6 | Yandex Plus «Turn off advertising» CTA | Нечего апселлить — рекламы и так нет |
| N7 | KeysShop / `isKeysShopEnabled` | Магазин ключей — монетизация |
| N8 | Yandex Metrika / GameAnalytics beacons | Приватность пользователя > атрибуция |
| N9 | `visibility_links` / `click_link` / `yclid` | То же |
| N10 | Legal-toggles «share purchase data with developers» | Покупок реальных нет |

**Дополнительно:** в SDK-стабе стоит **подменять `payingStatus` → `paying` и `hasPremium` → `true`**, чтобы внутриигровой premium-контент открывался для всех. Сейчас стаб этого не делает (см. `Resources/ya-sdk-stub.js`, прокидка `player` к real SDK без подмены).

---

## Что делаем (приоритизированный roadmap)

Приоритеты:
- **P0** — без этого игры ломаются или критичный UX недоступен.
- **P1** — заметные фичи, которые видит любой пользователь yandex.games в первые 30 секунд.
- **P2** — расширение полноты каталога и профиля.
- **P3** — приятные мелочи.

### P0. Критичное для запуска и сохранения игр

| # | Фича | Что делать | Источник в Yandex |
|---|---|---|---|
| 1 | **Cloud-save конфликт UI** | Pre-flight запрос `conflict_info` при старте `GameView`. Если `hasConflict: true` — показать native bottom-sheet с выбором «Data for account / Browser data» и пробросить выбор в SDK. Без этого Sprunki и подобные игры висят на preloader (та самая жалоба прошлой сессии). | `GET /games/api/catalogue/v2/conflict_info?app_id={id}` → `{ hasConflict, conflictInfo: { authUser, iGamesUsers } }` |
| 2 | **Cloud-save player.getData / setData** | Не блокировать SDK — пропускать вызовы напрямую к Yandex. Сейчас `ya-sdk-stub.js` пропускает, но без префлайт `conflict_info` (#1) часть игр виснет. | `GET/POST https://games-sdk.yandex.com/games/api/sdk/v1/player/data?app-id={id}` |
| 3 | **SDK player identity passthrough + premium override** | Пропускать настоящие `id`, `uniqueID`, `publicName`, `avatarIdHash`, `scopePermissions` от Yandex. **Подменять `payingStatus → 'paying'`, `hasPremium → true`**, чтобы платный контент открывался. | `GET https://games-sdk.yandex.com/games/api/sdk/v1/player?app-id={id}` |
| 4 | **`varioqub` feature-flags passthrough** | Пропускать без изменений — игры читают runtime-флаги для A/B. | `POST https://games-sdk.yandex.com/games/api/sdk/v1/varioqub/get_flags?app-id={id}` |
| 5 | **Native conflict-modal UI** | SwiftUI bottom-sheet под #1: аватар + login + dot, кнопка «Use account data», кнопка «Use browser data», копирайт сверху | UI Yandex (см. скриншот в аудите) |

### P1. Контентные поверхности (Home / каталог / detail)

| # | Фича | Что делать | Источник |
|---|---|---|---|
| 6 | **Tags system (569 тегов)** | Новый экран `TagsView` (грид по `/tags/`), `TagDetailView` (фильтр поиска по `tagId`), чипсы тегов под игрой в detail. | `GET /games/api/catalogue/v2/tags/?lang={lang}` → `{ tags: [{ id, title, slug, info.games_count, stat.rating }] }`; поле `tagIDs` уже приходит в каждом game-item feed-а |
| 7 | **Промо-карусель / hero rotator** | Top-of-Home: горизонтальная карусель с `gamesWithPromos`/`promos` из feed. Минусуем рекламные блоки. | `with_promos=true` в `/feed/`, top-level `promos` + `gamesWithPromos` |
| 8 | **Server-side recent games + cross-device** | Заменить локальный буфер «recent» на серверную историю — она синхронизируется между браузером и iOS. POST-ить факт запуска. | `POST /games/api/external/catalogue/v3/recent-games/` (Session_id cookie) |
| 9 | **`gqRating` + `badge`** | Поле `gqRating` (Yandex quality score) и `badge` («new», «editor's choice», ...) уже приходят в feed — добавить в `Game.swift`, рендерить на карточках. | Поля `gqRating`, `badge` в feed item |
| 10 | **Полный каталог `/all-games`** | Новый экран `AllGamesView` — бесконечный скролл всех игр. | URL `/games/all-games` (тот же `/feed/` без category-фильтра) |
| 11 | **«All categories» grid** | Новый `AllCategoriesView` — тайл-грид всех 29 категорий с обложками вместо chip-row. | `/games/categories` HTML или `categoryDataMappedByID` из app-data |
| 12 | **Total count в поиске** | Показывать «N games found» под input. | `totalGamesCount` в `/search/` ответе |
| 13 | **`features.user_data_required` бейдж** | На карточке: маленький значок «вход обязателен» там, где `user_data_required: true`. | `features` в feed item |
| 14 | **Server-rendered similarGames** | Перейти на `__appData__.similarGames` (16 игр) вместо отдельного `similar_games/` запроса — экономит запрос. | `__appData__.similarGames` в HTML |

### P1. Профиль (то, что игрок видит и чем пользуется)

| # | Фича | Что делать | Источник |
|---|---|---|---|
| 15 | **My games (server-side library)** | НЕ отдельный API. Yandex рендерит «played_games» rail в SSR HTML главной (`/games/`). Парсить `/games/` HTML под Session_id и доставать линки на app/{id} из rail с `block=played, card=your_games`. | SSR `/games/`, нет отдельного XHR |
| 16 | **Recovery code (P1, но эндпоинт TBD)** | Отдельный экран: input для кода + кнопка redeem. Эндпоинт в этом аудите не пойман (write-only, чтобы не мутировать чужой аккаунт). При имплементации — открыть DevTools, ввести любой реальный код в `/games/user`, поймать POST. | UI: `/games/user` recovery field |
| 17 | **Расширенный userData** | Добавить в `UserProfile`: `email`, `fio`, `isChild`, `isAccountCompletionAvailable`, `helpUrl`. | `__appData__.userData` |
| 18 | **Парсинг `isChild` для контентного гейта** | Если ребёнок — фильтровать 12+ контент в каталоге. | `userData.isChild` |
| 18b | **Notification settings (read)** | Прочитать `unsubscribes` array — это codes сабскрипшнов, от которых юзер отписан. Каждый code соответствует одному из 5 тогглов на `/games/user`. | `GET /games/api/catalogue/v2/unsubscribes` → `[]` (пустой массив = все включено) |
| 18c | **Legal toggles (read)** | `forbidPermissionsForAllApps` + `forbidSharePurchasesInfo` — два флага. Для нашей рамки (без monetization tracking) `forbidSharePurchasesInfo` всегда выставляем true. | `GET /games/api/catalogue/v2/userflags` → `{ flags: {...} }` |
| 18d | **UI settings (theme)** | Theme-предпочтение пользователя на сервере: `default` / `light` / `dark`. iOS может читать и применять. | `GET /games/api/catalogue/v2/user_info?settings=true` → `{ settings: { ui: { theme_type } } }` |

### P2. Поиск и обнаружение

| # | Фича | Что делать | Источник |
|---|---|---|---|
| 19 | **Search suggestions (client-side)** | У Yandex **нет** server-side suggest API — на typing суджесты не появляются, только submit. Поэтому для iOS suggest = client-only: prefix-match по локально кешированному `tags/` dictionary (569 тегов) + по последним searched + по топовым categories. | Локально, нет API |
| 20 | **История поиска** | UserDefaults / маленький store; показывать под input при focus. | Чисто клиентское |
| 21 | **Recommender API** | Использовать `recommenderApiUrl` для персонализированной ленты на Home (когда есть auth). | `__appData__.recommenderApiUrl` = `https://games.yandex.com/games/api`. Сабпуть TBD при имплементации. |
| 22 | **Games AI entry-point** | UI-копия Yandex: правый side-panel chat. Greeting: «Hi! I'll help you find the right game. Describe the plot, genre, or mood, and I'll choose the options.» Quick-tags: «For one player», «With a rival», «More options». Free-text input + send. Эндпоинт чат-комплитов в этом аудите не пойман (write — пропустил намеренно). | UI расшифрован; chat endpoint TBD |

### P2. Игровая сессия (in-game UX)

| # | Фича | Что делать | Источник |
|---|---|---|---|
| 23 | **In-game header overlay** | SwiftUI overlay поверх `WKWebView` сверху ~40pt: иконка «домой», название игры, кнопка fullscreen, меню с настройками. **Без** Yans/Plus — оставить только функциональные. | Скриншот yandex.games в аудите |
| 24 | **Achievements UI** | Endpoint `https://games-sdk.yandex.com/games/api/sdk/v1/achievements/?app-id={id}` существует, но требует SDK Bearer token — выдается только внутри iframe. Два пути: (a) прокидывать SDK passthrough и собирать unlocked-данные в native через message-bridge во время игры; (b) показывать achievements list только когда игра запущена (внутри `GameView`), без отдельного экрана в Profile. Рекомендую (b) — проще. | SDK endpoint 401 без токена |
| 25 | **Leaderboards UI** | На detail HTML Yandex кладёт `leaderboards: { appId, list, main, friends, display, data, defaultLeaderboardName }` в SSR. iOS может парсить и показывать native лидерборд под игрой (или в overlay внутри `GameView`). | `__appData__.leaderboards` в HTML game-detail |

### P2. Локализация

| # | Фича | Что делать | Источник |
|---|---|---|---|
| 26 | **20+ языков** | Добавить в `Localizable.xcstrings`: ar, az, be, fa, he, hi, hy, id, ja, ka, kk, sr, th, tk, tr, uk, uz, vi (плюс уже есть en, ru). Передавать `lang` во все API. | Yandex поддерживает все эти TLD |
| 27 | **RTL layout** | Audit SwiftUI: заменить `.padding(.leading/.trailing)` где надо, `Image(systemName:)` на mirror-aware иконки, проверить `LocalizedStringKey`. | iOS layout audit |
| 28 | **TLD routing расширение** | Сейчас yandex.com / yandex.ru. Добавить .by, .kz, .uz, .com.tr, .com.am, .az по локали устройства. | `CatalogService.resolveHost` |

### P3. Социальные и приятные мелочи

| # | Фича | Что делать | Источник |
|---|---|---|---|
| 29 | **Developer pages** | Ссылка с detail на `/games/developer/{slug}` + список игр студии. | URL pattern + HTML scrape |
| 30 | **Friends-leaderboards** | Раздел «друзья» в leaderboard-экране (#25). | `leaderboards.friends` |
| 31 | **Notification settings UI** (только для информации, без push на iOS пока) | Переключатели как у Yandex — но фактически без APN-инфраструктуры это no-op. Можно отложить. | `/user_info?settings=true` |
| 32 | **Push (APNs)** | Если когда-нибудь захочется — отдельный большой кусок. | — |

---

## Критичные файлы для будущей реализации

- `ios/UGames/Resources/ya-sdk-stub.js` — добавить `conflict_info` префлайт (#1), подмену `payingStatus`/`hasPremium` (#3)
- `ios/UGames/WebView/GameWebView.swift` — bridge для conflict-modal (#5), in-game overlay (#23)
- `ios/UGames/Views/GameView.swift` — overlay-header (#23) и conflict-modal (#5)
- `ios/UGames/Catalog/CatalogService.swift` — все новые API (conflict_info, recent-games server, tags, recommender, search totals)
- `ios/UGames/Catalog/Game.swift` + `AppDetail.swift` — `gqRating`, `badge`, `tagIDs`, `features`. Поля `visibility_links`/`click_link`/`yclid` **игнорировать** (см. N8/N9).
- `ios/UGames/Catalog/UserProfile.swift` — расширение полей (#17)
- `ios/UGames/Views/HomeView.swift` + `HomeViewModel.swift` — промо-карусель (#7), бейджи (#9), серверный recent (#8)
- `ios/UGames/Views/BrowseView.swift` — total counter (#12), suggestions (#19), история (#20)
- Новые экраны: `TagsView`, `TagDetailView`, `AllGamesView`, `AllCategoriesView`, `LibraryView`, `RecoveryCodeView`, `LeaderboardsView`, `AchievementsView`, `DeveloperView`
- `ios/UGames/Localizable.xcstrings` — расширение языков (#26)

---

## Что ещё нужно дополнительно изучить

После расширенного аудита остались только **3 write-only эндпоинта**, которые нельзя пробить read-only-методами без мутации чужого аккаунта. Поймать их можно за ~10 минут в DevTools, когда дойдём до конкретной фичи и будут собственные тестовые данные:

1. **Recovery code redeem POST** — ввести реальный код в `/games/user`, поймать запрос. Скорее всего `POST /games/api/catalogue/v2/recovery_code/redeem`.
2. **Notification settings PUT/POST** — переключить любой тоггл на `/games/user`, поймать запрос. Скорее всего `POST /games/api/catalogue/v2/unsubscribes` с `{ codes: [...] }`.
3. **Games AI chat completion** — отправить сообщение в правый чат-панель, поймать XHR.

**Подтверждено в этом аудите (раньше TBD):**

- ✅ Search-suggest: его **нет** на yandex.com/games. На iOS делаем client-side (history + tags prefix).
- ✅ Achievements API: `https://games-sdk.yandex.com/games/api/sdk/v1/achievements/?app-id={id}` — требует SDK Bearer (только из iframe).
- ✅ My games library: server-side rendered в HTML главной, без отдельного XHR. Парсим SSR.
- ✅ Notification settings GET: `/games/api/catalogue/v2/unsubscribes` (Array of codes), `/userflags` (`{ flags }`), `/user_info?settings=true` (`{ subscriptions, settings.ui.theme_type }`).
- ✅ Games AI UI: правый side-panel chat, greeting + 3 quick-tag chip + free text input.

---

## Phase 2: Visual Redesign Pass (после approve этого плана)

После того как roadmap фич утверждён, следующий шаг — **полный визуальный редизайн под Apple Liquid Glass (iOS 26)** через GAN design loop (skill `everything-claude-code:gan-design`). 

**Visual language:**
- Translucent surfaces, glass-morphism (`Material.regular`, `Material.thick`)
- Depth через layered blur + subtle shadows
- Native SF Symbols + SF Pro typography (никаких custom font-stacks)
- Dark theme как primary (gaming context); light как secondary
- Accent gradient под gaming feel, без подражания yandex-фиолетовому

**Scope (полный редизайн):**

Существующие экраны переделать:
- `HomeView` — заменить hero/genre rows на glass-cards с blurred cover backdrop, добавить promo-карусель (#7), бейджи `gqRating` (#9), серверный recent (#8)
- `BrowseView` — новый search header с glass-input, total counter (#12), client-side suggest (#19), история (#20)
- `FavoritesView` — переименовать в Library, объединить favorites + server `lastPlayedTS` (#15)
- `ProfileView` — переделать под Yandex-аналог с тогглами, recovery code, расширенным userData; убрать Yans/Plus
- `GameDetailView` — переход на server-rendered similarGames (#14), tag-чипсы (#28), leaderboards-блок (#25), `gqRating` бейдж
- `GameView` — добавить native overlay-header (#23) и conflict-modal (#5) с glass-treatment

Новые экраны спроектировать с нуля:
- `TagsView` / `TagDetailView` (#6)
- `AllGamesView` (#10), `AllCategoriesView` (#11)
- `RecoveryCodeView` (#16)
- `LeaderboardsView` (#25)
- `AchievementsOverlay` (#24, in-game)
- `DeveloperView` (#29)

**GAN design loop протокол:**
1. **Generator** агент (sonnet) пишет SwiftUI-моки для одного экрана за итерацию: компонентная структура, state, modifiers, glass-Material wrapping. Output — файлы под `ios/UGames/Views/Designs/{ScreenName}V2.swift` (или scratch-файлы).
2. **Evaluator** агент (opus) оценивает по rubric: соответствие Liquid Glass guidelines, accessibility (Dynamic Type, VoiceOver, reduce-motion), консистентность с другими экранами, фактическое покрытие новых фич из roadmap. Выдает score и список fix-and-go.
3. **Bounded iterations**: max 3 цикла на экран. Финальный score должен быть >= 8/10.
4. После прохода всех экранов — общий integration review: единый design system module под `ios/UGames/DesignSystem/` (tokens, materials, spacing, typography).

**Verification design-pass:**
- Каждый mock запускается в Xcode preview (или iOS симулятор) и проверяется визуально на iPhone 15 Pro / iPhone SE viewport
- VoiceOver pass на каждом экране
- Reduce Motion / Reduce Transparency fallbacks
- Light/Dark mode parity
- RTL preview (`.environment(\.layoutDirection, .rightToLeft)`)

---

## Verification (для feature roadmap)

Документ — справочный roadmap, без E2E-теста. Проверить полноту:

1. Открыть yandex.com/games под живой сессией, пройти по списку и убедиться, что фичи всё ещё на месте (Yandex периодически меняет UI)
2. Открыть текущий iOS в симуляторе и mark, что отсутствует — это negative-claims проверка
3. По эндпоинтам с конкретным URL: `curl --cookie` с экспортом Session_id, статус 200
