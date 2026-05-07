# U-Games Redesign — Phase 1: Foundation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Заложить фундамент premium-редизайна — theme tokens, базовые UI-компоненты (Skeleton, EmptyState, ErrorState, GameCard×3, Hero/StoryCard stubs, GenreChipRow, FloatingTabBar), расширить `Game` модель полями `mainColor / iconMainColor / videoUrl`, добавить media3 (Android), обернуть оба приложения в bottom-tab scaffold с единственным «Home»-табом, рендерящим существующий `CatalogScreen` / `CatalogView`. После этой фазы внешне ничего не меняется (старый каталог продолжает работать), но всё готово для Phase 2.

**Architecture:** Параллельно реализуется на Android (Kotlin/Compose) и iOS (Swift/SwiftUI). Старый код не удаляем — заменяем на новых местах в Phase 2-3. Tab scaffold изолирует существующий каталог в один таб, остальные 3 таба — заглушки `EmptyState("Coming soon")`. Это даёт зелёный билд после каждой задачи и независимое тестирование компонентов.

**Tech Stack:** Kotlin 2.0 + Jetpack Compose Material3 + Ktor, Swift 5.9 + SwiftUI iOS 16+, AndroidX Media3 1.4 / AVKit (для будущего Hero-видео), Coil / AsyncImage.

**Spec:** [`../specs/2026-05-05-ui-ux-redesign-design.md`](../specs/2026-05-05-ui-ux-redesign-design.md)

**Out of scope this phase:** Home/Browse/Favorites/Profile-экраны (Phase 2), GameDetail (Phase 3), in-game overlay (Phase 4), удаление старого кода (Phase 5).

---

## File structure (после фазы)

### Android — новые

| Path | Что |
|---|---|
| `android/app/src/main/kotlin/games/yandex/wrap/ui/theme/Hex.kt` | `parseHexColor(String?): Color?` |
| `android/app/src/main/kotlin/games/yandex/wrap/ui/theme/Color.kt` | Цветовые токены (`UGColors` object) |
| `android/app/src/main/kotlin/games/yandex/wrap/ui/theme/Type.kt` | Типографика (`UGType` object) |
| `android/app/src/main/kotlin/games/yandex/wrap/ui/theme/UGamesTheme.kt` | `@Composable UGamesTheme(content)` — обёртка |
| `android/app/src/main/kotlin/games/yandex/wrap/ui/components/Skeleton.kt` | Shimmer placeholder |
| `android/app/src/main/kotlin/games/yandex/wrap/ui/components/EmptyState.kt` | Иконка + title + body + CTA |
| `android/app/src/main/kotlin/games/yandex/wrap/ui/components/ErrorState.kt` | Сообщение + Retry |
| `android/app/src/main/kotlin/games/yandex/wrap/ui/components/GameCard.kt` | `TileGameCard`, `WideGameCard`, `SquareGameCard` |
| `android/app/src/main/kotlin/games/yandex/wrap/ui/components/Hero.kt` | `HeroSection` (стаб — пока без видео) |
| `android/app/src/main/kotlin/games/yandex/wrap/ui/components/StoryCard.kt` | `StoryCard` |
| `android/app/src/main/kotlin/games/yandex/wrap/ui/components/GenreChipRow.kt` | Sticky chips |
| `android/app/src/main/kotlin/games/yandex/wrap/ui/components/FloatingTabBar.kt` | Glass tab-bar (с API 31+ blur fallback) |

### Android — изменяемые

| Path | Что |
|---|---|
| `android/app/src/main/kotlin/games/yandex/wrap/catalog/Game.kt` | +поля `mainColor / iconMainColor / videoUrl` |
| `android/app/src/main/kotlin/games/yandex/wrap/catalog/CatalogApi.kt` | парсинг новых полей в `itemToGame` |
| `android/app/build.gradle.kts` | +media3 |
| `android/gradle/libs.versions.toml` | +media3 версии |
| `android/app/src/main/kotlin/games/yandex/wrap/MainActivity.kt` | оборачиваем `setContent { UGamesTheme { TabContainer(...) } }` |

### iOS — новые

| Path | Что |
|---|---|
| `ios/UGames/Theme/Hex.swift` | `Color(hex: String)` extension |
| `ios/UGames/Theme/Theme.swift` | Цвета + шрифты |
| `ios/UGames/Components/Skeleton.swift` | Shimmer placeholder |
| `ios/UGames/Components/EmptyState.swift` | Иконка + title + body + CTA |
| `ios/UGames/Components/ErrorState.swift` | Сообщение + Retry |
| `ios/UGames/Components/GameCard.swift` | `TileGameCard`, `WideGameCard`, `SquareGameCard` |
| `ios/UGames/Components/Hero.swift` | `HeroSection` (стаб) |
| `ios/UGames/Components/StoryCard.swift` | `StoryCard` |
| `ios/UGames/Components/GenreChipRow.swift` | Chips |
| `ios/UGames/Components/FloatingTabBar.swift` | Glass tab-bar |

### iOS — изменяемые

| Path | Что |
|---|---|
| `ios/UGames/Catalog/Game.swift` | +поля `mainColor / iconMainColor / videoUrl` |
| `ios/UGames/Catalog/CatalogService.swift` | парсинг новых полей |
| `ios/UGames/UGamesApp.swift` | `RootView` оборачивается в `TabContainer` (TabView с 4 табами) |

---

## Conventions

- **Все новые Compose-композаблы** — `@Composable fun ИмяComponent(...)` без `MaterialTheme.*`-внутри. Цвет/типография — через `UGColors` / `UGType`.
- **Все новые SwiftUI views** — `struct ИмяComponent: View { var body: some View {...} }`. Цвет через `UGColor.<token>`, шрифт через `UGFont.<style>`.
- **Превью**: для каждого Compose-компонента — `@Preview` с тёмной темой; для SwiftUI — `#Preview`. Это автоматическая визуальная проверка.
- **Никакого нового форматирования старых файлов** кроме перечисленных. Сохраняем стиль соседних файлов (4-spaces Kotlin / 4-spaces Swift).
- **Каждая задача ≤ 5 минут**. Каждая задача = 1 commit.
- **Минимум новых зависимостей**: только `androidx.media3:media3-exoplayer/ui` 1.4.1 (Android). iOS — system AVKit, без CocoaPods/SPM-добавок.
- **Тесты**: Phase 1 не добавляет test-infra (её нет в проекте сейчас). Верификация — `./gradlew :app:assembleDebug` зелёный + ручной запуск приложения (старый каталог должен работать как раньше).

---

## Task overview

| # | Task | Platform | Verify |
|---|---|---|---|
| 1 | Hex parser | Android | компилируется |
| 2 | Color tokens | Android | компилируется |
| 3 | Typography tokens | Android | компилируется |
| 4 | UGamesTheme wrapper | Android | компилируется + applies в MainActivity |
| 5 | Game model fields | Android | компилируется |
| 6 | CatalogApi parsing | Android | компилируется |
| 7 | media3 dependency | Android | сборка зелёная, app запускается |
| 8 | Skeleton component | Android | preview рендерит |
| 9 | EmptyState component | Android | preview рендерит |
| 10 | ErrorState component | Android | preview рендерит |
| 11 | TileGameCard | Android | preview рендерит |
| 12 | WideGameCard | Android | preview рендерит |
| 13 | SquareGameCard | Android | preview рендерит |
| 14 | HeroSection (stub) | Android | preview рендерит |
| 15 | StoryCard | Android | preview рендерит |
| 16 | GenreChipRow | Android | preview рендерит |
| 17 | FloatingTabBar | Android | preview рендерит |
| 18 | TabContainer + MainActivity wiring | Android | приложение запускается, видны 4 таба, Home показывает старый CatalogScreen |
| 19 | Hex extension | iOS | компилируется |
| 20 | Theme tokens | iOS | компилируется |
| 21 | Game model fields | iOS | компилируется |
| 22 | CatalogService parsing | iOS | компилируется |
| 23 | Skeleton component | iOS | preview рендерит |
| 24 | EmptyState component | iOS | preview рендерит |
| 25 | ErrorState component | iOS | preview рендерит |
| 26 | TileGameCard | iOS | preview рендерит |
| 27 | WideGameCard | iOS | preview рендерит |
| 28 | SquareGameCard | iOS | preview рендерит |
| 29 | HeroSection (stub) | iOS | preview рендерит |
| 30 | StoryCard | iOS | preview рендерит |
| 31 | GenreChipRow | iOS | preview рендерит |
| 32 | FloatingTabBar | iOS | preview рендерит |
| 33 | TabContainer + UGamesApp wiring | iOS | приложение запускается, видны 4 таба, Home показывает старый CatalogView |

---

## Tasks

### Task 1: Android — Hex parser

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/theme/Hex.kt`

- [ ] **Step 1: Create file with parseHexColor**

```kotlin
package games.yandex.wrap.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Parse a "#RRGGBB" or "#AARRGGBB" hex string into a Compose [Color]. Returns
 * null for blank, malformed, or wrong-length strings — callers should fall
 * back to a default (e.g. UGColors.Surface).
 *
 * Yandex catalog feed exposes mainColor as "#41B4F6" lowercase or uppercase.
 */
fun parseHexColor(hex: String?): Color? {
    if (hex.isNullOrBlank()) return null
    val cleaned = hex.removePrefix("#")
    return when (cleaned.length) {
        6 -> runCatching { Color(("ff$cleaned").toLong(16)) }.getOrNull()
        8 -> runCatching { Color(cleaned.toLong(16)) }.getOrNull()
        else -> null
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd android && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/games/yandex/wrap/ui/theme/Hex.kt
git commit -m "feat(android): add parseHexColor utility for mainColor parsing"
```

---

### Task 2: Android — Color tokens

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/theme/Color.kt`

- [ ] **Step 1: Create UGColors object**

```kotlin
package games.yandex.wrap.ui.theme

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/**
 * U-Games premium palette. Token names match the spec
 * (docs/superpowers/specs/2026-05-05-ui-ux-redesign-design.md).
 */
object UGColors {
    val Bg0 = Color(0xFF000000)
    val Surface = Color(0xFF0D0D10)
    val Elevated = Color(0xFF1A1A20)
    val Divider = Color(0xFF1F1F22)

    val TextPrimary = Color(0xFFFFFFFF)
    val TextSecondary = Color(0xFFC8C8D0)
    val TextMuted = Color(0xFF7A7A82)

    val Accent = Color(0xFFFFC700)
    val AccentEnd = Color(0xFFFF7E00)
    val Danger = Color(0xFFFF4D6A)

    /** Glass surface fallback for API < 31 (no blur). */
    val GlassFallback = Color(0xCC141418)

    /** 35% opacity glow used in shadow tints — see Modifier.coloredHalo. */
    val HaloAlpha = 0.35f
    /** 18% opacity inset border. */
    val HaloBorderAlpha = 0.18f

    val AccentGradient: Brush = Brush.linearGradient(
        colors = listOf(Accent, AccentEnd),
    )
}
```

- [ ] **Step 2: Build to verify**

Run: `cd android && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/games/yandex/wrap/ui/theme/Color.kt
git commit -m "feat(android): add UGColors palette tokens"
```

---

### Task 3: Android — Typography tokens

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/theme/Type.kt`

- [ ] **Step 1: Create UGType object**

```kotlin
package games.yandex.wrap.ui.theme

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * U-Games typography tokens. Names match the spec table.
 * Uses the system font (no custom font asset).
 */
object UGType {
    val DisplayXL = TextStyle(
        fontSize = 34.sp, fontWeight = FontWeight.Black, letterSpacing = (-1.0).sp,
    )
    val Display = TextStyle(
        fontSize = 30.sp, fontWeight = FontWeight.Black, letterSpacing = (-0.8).sp,
    )
    val TitleL = TextStyle(
        fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.5).sp,
    )
    val TitleM = TextStyle(
        fontSize = 18.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.3).sp,
    )
    val Body = TextStyle(
        fontSize = 15.sp, fontWeight = FontWeight.Normal,
    )
    val BodyS = TextStyle(
        fontSize = 13.sp, fontWeight = FontWeight.Medium,
    )
    val Label = TextStyle(
        fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.2.sp,
    )
    val Caption = TextStyle(
        fontSize = 10.sp, fontWeight = FontWeight.Bold,
    )
}
```

- [ ] **Step 2: Build**

Run: `cd android && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/games/yandex/wrap/ui/theme/Type.kt
git commit -m "feat(android): add UGType typography tokens"
```

---

### Task 4: Android — UGamesTheme wrapper

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/theme/UGamesTheme.kt`

- [ ] **Step 1: Create wrapper composable**

```kotlin
package games.yandex.wrap.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

/**
 * Wraps content in MaterialTheme(darkColorScheme()) plus a black Surface so
 * legacy MaterialTheme.* lookups still work, but new code reads UGColors /
 * UGType directly.
 */
@Composable
fun UGamesTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = darkColorScheme()) {
        Surface(color = UGColors.Bg0, content = content)
    }
}
```

- [ ] **Step 2: Build**

Run: `cd android && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Swap MaterialTheme to UGamesTheme in MainActivity**

Edit `android/app/src/main/kotlin/games/yandex/wrap/MainActivity.kt`. Replace imports:

```kotlin
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
```

with:

```kotlin
import games.yandex.wrap.ui.theme.UGamesTheme
```

Replace inside `setContent { ... }`:

```kotlin
            MaterialTheme(colorScheme = darkColorScheme()) {
                Surface(color = Color.Black) {
```

with:

```kotlin
            UGamesTheme {
```

Adjust the matching closing braces (one fewer level of indentation needed). Remove the now-unused `import androidx.compose.ui.graphics.Color`.

- [ ] **Step 4: Build and run**

Run: `cd android && ./gradlew :app:assembleDebug`
Expected: BUILD SUCCESSFUL.

Manual: install APK, launch, verify catalog screen still renders with black background (visually identical).

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/games/yandex/wrap/ui/theme/UGamesTheme.kt android/app/src/main/kotlin/games/yandex/wrap/MainActivity.kt
git commit -m "feat(android): wrap MainActivity in UGamesTheme"
```

---

### Task 5: Android — Game model fields

**Files:**
- Modify: `android/app/src/main/kotlin/games/yandex/wrap/catalog/Game.kt`

- [ ] **Step 1: Read current Game.kt**

Run: `cat android/app/src/main/kotlin/games/yandex/wrap/catalog/Game.kt`

Note the current field list. Expected: `appId, title, rating, ratingCount, coverUrl, iconUrl, categories, developer`.

- [ ] **Step 2: Add new fields**

Add three new fields with defaults (so callers compile without source changes). The full data class becomes:

```kotlin
data class Game(
    val appId: Long,
    val title: String,
    val rating: Float,
    val ratingCount: Int,
    val coverUrl: String,
    val iconUrl: String,
    val categories: List<String>,
    val developer: String,
    /** Hex like "#41B4F6". Used for halo glow + image placeholder. */
    val mainColor: String? = null,
    /** Hex of the icon's mainColor. Used for square cards (recently row). */
    val iconMainColor: String? = null,
    /** Direct mp4 URL from media.videos[0].mp4StreamUrl, for Hero autoplay. */
    val videoUrl: String? = null,
)
```

(Preserve any annotations and additional fields/imports the existing file has — diff against the original.)

- [ ] **Step 3: Build**

Run: `cd android && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/kotlin/games/yandex/wrap/catalog/Game.kt
git commit -m "feat(android): extend Game with mainColor, iconMainColor, videoUrl"
```

---

### Task 6: Android — CatalogApi parsing

**Files:**
- Modify: `android/app/src/main/kotlin/games/yandex/wrap/catalog/CatalogApi.kt` (the `itemToGame` private function near line 279)

- [ ] **Step 1: Replace itemToGame to parse new fields**

Find the existing `itemToGame` function and replace its body:

```kotlin
    private fun itemToGame(item: JsonObject): Game? {
        val appId = item["appID"]?.jsonPrimitive?.longOrNull ?: return null
        val title = item["title"]?.jsonPrimitive?.contentOrNull ?: return null
        val rating = item["rating"]?.jsonPrimitive?.floatOrNull ?: 0f
        val ratingCount = item["ratingCount"]?.jsonPrimitive?.intOrNull ?: 0
        val media = item["media"] as? JsonObject
        val coverObj = media?.get("cover") as? JsonObject
        val iconObj = media?.get("icon") as? JsonObject
        val coverPrefix = coverObj?.get("prefix-url")?.jsonPrimitive?.contentOrNull
        val iconPrefix = iconObj?.get("prefix-url")?.jsonPrimitive?.contentOrNull
        val mainColor = coverObj?.get("mainColor")?.jsonPrimitive?.contentOrNull
        val iconMainColor = iconObj?.get("mainColor")?.jsonPrimitive?.contentOrNull
        val videoUrl = (media?.get("videos") as? JsonArray)
            ?.firstOrNull()
            ?.let { it as? JsonObject }
            ?.get("mp4StreamUrl")?.jsonPrimitive?.contentOrNull
        val categories = (item["categoriesNames"] as? JsonElement)
            ?.let { it as? JsonArray }
            ?.mapNotNull { it.jsonPrimitive.contentOrNull }
            ?: emptyList()
        val developer = (item["developer"] as? JsonObject)
            ?.get("name")?.jsonPrimitive?.contentOrNull
            ?: ""
        return Game(
            appId = appId,
            title = title,
            rating = rating,
            ratingCount = ratingCount,
            coverUrl = coverPrefix?.let { it + COVER_SIZE } ?: "",
            iconUrl = iconPrefix?.let { it + ICON_SIZE } ?: coverPrefix?.let { it + ICON_SIZE } ?: "",
            categories = categories,
            developer = developer,
            mainColor = mainColor,
            iconMainColor = iconMainColor,
            videoUrl = videoUrl,
        )
    }
```

- [ ] **Step 2: Build**

Run: `cd android && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/games/yandex/wrap/catalog/CatalogApi.kt
git commit -m "feat(android): parse mainColor, iconMainColor, videoUrl from feed"
```

---

### Task 7: Android — media3 dependency

**Files:**
- Modify: `android/gradle/libs.versions.toml`
- Modify: `android/app/build.gradle.kts`

- [ ] **Step 1: Add media3 entries to libs.versions.toml**

In `[versions]` add:

```toml
media3 = "1.4.1"
```

In `[libraries]` add:

```toml
androidx-media3-exoplayer = { module = "androidx.media3:media3-exoplayer", version.ref = "media3" }
androidx-media3-ui = { module = "androidx.media3:media3-ui", version.ref = "media3" }
```

- [ ] **Step 2: Wire dependencies in app/build.gradle.kts**

Add to `dependencies { ... }`, after `implementation(libs.coil.compose)`:

```kotlin
    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.ui)
```

- [ ] **Step 3: Build (forces gradle to resolve)**

Run: `cd android && ./gradlew :app:assembleDebug`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Commit**

```bash
git add android/gradle/libs.versions.toml android/app/build.gradle.kts
git commit -m "build(android): add androidx.media3 1.4.1 for Hero video playback"
```

---

### Task 8: Android — Skeleton component

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/components/Skeleton.kt`

- [ ] **Step 1: Create Skeleton with shimmer**

```kotlin
package games.yandex.wrap.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGamesTheme

/**
 * Animated shimmer placeholder. Use for any "loading game tile / hero" hole
 * that used to show CircularProgressIndicator. Color sweeps Elevated → lighter
 * shade → Elevated to imply ongoing activity without spinner-fatigue.
 */
@Composable
fun Skeleton(
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 12.dp,
) {
    val transition = rememberInfiniteTransition(label = "skeleton")
    val phase by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1400, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "phase",
    )
    val brush = Brush.linearGradient(
        colors = listOf(
            UGColors.Elevated,
            Color(0xFF22222A),
            UGColors.Elevated,
        ),
        start = Offset(phase * 600f - 300f, 0f),
        end = Offset(phase * 600f, 0f),
    )
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(cornerRadius))
            .background(brush),
    )
}

@Preview(showBackground = true, backgroundColor = 0xFF000000)
@Composable
private fun SkeletonPreview() {
    UGamesTheme {
        Skeleton(
            modifier = Modifier
                .padding(16.dp)
                .height(120.dp)
                .fillMaxWidth(),
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `cd android && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/games/yandex/wrap/ui/components/Skeleton.kt
git commit -m "feat(android): add Skeleton shimmer component"
```

---

### Task 9: Android — EmptyState component

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/components/EmptyState.kt`

- [ ] **Step 1: Create EmptyState**

```kotlin
package games.yandex.wrap.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType
import games.yandex.wrap.ui.theme.UGamesTheme

/**
 * Empty-state placard: 48dp icon, title, body, optional CTA.
 *
 * Used for "No favorites yet", "No games match search", "Coming soon" tabs.
 */
@Composable
fun EmptyState(
    icon: ImageVector,
    title: String,
    body: String? = null,
    ctaLabel: String? = null,
    onCta: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = UGColors.TextMuted,
            modifier = Modifier.size(48.dp),
        )
        Spacer(Modifier.height(14.dp))
        Text(text = title, color = UGColors.TextPrimary, style = UGType.TitleM)
        if (!body.isNullOrEmpty()) {
            Spacer(Modifier.height(6.dp))
            Text(
                text = body,
                color = UGColors.TextMuted,
                style = UGType.BodyS,
                textAlign = TextAlign.Center,
            )
        }
        if (ctaLabel != null && onCta != null) {
            Spacer(Modifier.height(16.dp))
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(14.dp))
                    .background(UGColors.AccentGradient)
                    .clickable(onClick = onCta)
                    .padding(horizontal = 18.dp, vertical = 10.dp),
            ) {
                Text(text = ctaLabel, color = Color.Black, style = UGType.BodyS)
            }
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, widthDp = 360, heightDp = 320)
@Composable
private fun EmptyStatePreview() {
    UGamesTheme {
        EmptyState(
            icon = Icons.Filled.FavoriteBorder,
            title = "No favorites yet",
            body = "Tap ♥ on any game to save it.",
            ctaLabel = "Browse games",
            onCta = {},
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `cd android && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/games/yandex/wrap/ui/components/EmptyState.kt
git commit -m "feat(android): add EmptyState component"
```

---

### Task 10: Android — ErrorState component

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/components/ErrorState.kt`

- [ ] **Step 1: Create ErrorState**

```kotlin
package games.yandex.wrap.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType
import games.yandex.wrap.ui.theme.UGamesTheme

/** Inline error placard with Retry. Replaces ad-hoc error+TextButton blocks. */
@Composable
fun ErrorState(
    message: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = Icons.Filled.WifiOff,
            contentDescription = null,
            tint = UGColors.TextMuted,
            modifier = Modifier.size(48.dp),
        )
        Spacer(Modifier.height(14.dp))
        Text(text = "Couldn't load", color = UGColors.TextPrimary, style = UGType.TitleM)
        Spacer(Modifier.height(6.dp))
        Text(
            text = message,
            color = UGColors.TextMuted,
            style = UGType.BodyS,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(16.dp))
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(14.dp))
                .background(UGColors.AccentGradient)
                .clickable(onClick = onRetry)
                .padding(horizontal = 18.dp, vertical = 10.dp),
        ) {
            Text(text = "Try again", color = Color.Black, style = UGType.BodyS)
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, widthDp = 360, heightDp = 320)
@Composable
private fun ErrorStatePreview() {
    UGamesTheme {
        ErrorState(message = "Check your connection and try again.", onRetry = {})
    }
}
```

- [ ] **Step 2: Build**

Run: `cd android && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/games/yandex/wrap/ui/components/ErrorState.kt
git commit -m "feat(android): add ErrorState component"
```

---

### Task 11: Android — TileGameCard

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/components/GameCard.kt`

- [ ] **Step 1: Create GameCard.kt with TileGameCard**

```kotlin
package games.yandex.wrap.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import games.yandex.wrap.catalog.Game
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType
import games.yandex.wrap.ui.theme.UGamesTheme
import games.yandex.wrap.ui.theme.parseHexColor

/**
 * Tile card for grids (Browse / Favorites / Similar).
 *
 * - Cover at 16:10 with mainColor placeholder fallback (no grey flash).
 * - Heart toggle top-right on a glass-circle.
 * - Rating pill bottom-left.
 * - Halo: shadow tinted by mainColor, falls back to Accent if unknown.
 * - Title 2 lines max, meta 1 line.
 */
@Composable
fun TileGameCard(
    game: Game,
    isFavorite: Boolean,
    onClick: () -> Unit,
    onFavoriteToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val haloColor = parseHexColor(game.mainColor) ?: UGColors.Accent
    val placeholder = parseHexColor(game.mainColor) ?: UGColors.Elevated

    Column(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .clickable(onClick = onClick),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(16f / 10f)
                .shadow(
                    elevation = 12.dp,
                    shape = RoundedCornerShape(16.dp),
                    clip = false,
                    ambientColor = haloColor.copy(alpha = UGColors.HaloAlpha),
                    spotColor = haloColor.copy(alpha = UGColors.HaloAlpha),
                )
                .clip(RoundedCornerShape(16.dp))
                .background(placeholder)
                .border(
                    width = 1.dp,
                    color = haloColor.copy(alpha = UGColors.HaloBorderAlpha),
                    shape = RoundedCornerShape(16.dp),
                ),
        ) {
            AsyncImage(
                model = game.coverUrl,
                contentDescription = game.title,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxWidth().aspectRatio(16f / 10f),
            )
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(8.dp)
                    .size(30.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.55f))
                    .clickable(onClick = onFavoriteToggle),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = if (isFavorite) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                    contentDescription = if (isFavorite) "Remove from favorites" else "Add to favorites",
                    tint = if (isFavorite) UGColors.Danger else UGColors.TextPrimary,
                    modifier = Modifier.size(16.dp),
                )
            }
            if (game.ratingCount > 0) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(8.dp)
                        .clip(RoundedCornerShape(999.dp))
                        .background(Color.Black.copy(alpha = 0.55f))
                        .padding(horizontal = 8.dp, vertical = 3.dp),
                ) {
                    Text(
                        text = "★ %.1f".format(game.rating),
                        color = UGColors.Accent,
                        style = UGType.Caption,
                    )
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(
            text = game.title,
            color = UGColors.TextPrimary,
            style = UGType.BodyS,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        val meta = listOfNotNull(
            game.categories.firstOrNull(),
            if (game.ratingCount > 0) "${game.ratingCount} ratings" else null,
        ).joinToString(" · ")
        if (meta.isNotEmpty()) {
            Text(
                text = meta,
                color = UGColors.TextMuted,
                style = UGType.Caption,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, widthDp = 200, heightDp = 220)
@Composable
private fun TileGameCardPreview() {
    UGamesTheme {
        TileGameCard(
            game = Game(
                appId = 1, title = "Block Puzzle: Falling Shapes",
                rating = 4.9f, ratingCount = 39,
                coverUrl = "", iconUrl = "",
                categories = listOf("Puzzle"), developer = "studio",
                mainColor = "#41B4F6",
            ),
            isFavorite = true,
            onClick = {}, onFavoriteToggle = {},
            modifier = Modifier.padding(12.dp),
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `cd android && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/games/yandex/wrap/ui/components/GameCard.kt
git commit -m "feat(android): add TileGameCard with mainColor halo"
```

---

### Task 12: Android — WideGameCard

**Files:**
- Modify: `android/app/src/main/kotlin/games/yandex/wrap/ui/components/GameCard.kt`

- [ ] **Step 1: Append WideGameCard composable**

After the `TileGameCardPreview` function and before the file's EOF, append:

```kotlin
/**
 * Wide card (140×96) for Continue / Trending / Favorites rows on Home.
 * Title overlaid bottom, full-bleed cover, halo by mainColor.
 */
@Composable
fun WideGameCard(
    game: Game,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val haloColor = parseHexColor(game.mainColor) ?: UGColors.Accent
    val placeholder = parseHexColor(game.mainColor) ?: UGColors.Elevated
    Box(
        modifier = modifier
            .size(width = 140.dp, height = 96.dp)
            .shadow(
                elevation = 12.dp,
                shape = RoundedCornerShape(16.dp),
                clip = false,
                ambientColor = haloColor.copy(alpha = UGColors.HaloAlpha),
                spotColor = haloColor.copy(alpha = UGColors.HaloAlpha),
            )
            .clip(RoundedCornerShape(16.dp))
            .background(placeholder)
            .border(
                width = 1.dp,
                color = haloColor.copy(alpha = UGColors.HaloBorderAlpha),
                shape = RoundedCornerShape(16.dp),
            )
            .clickable(onClick = onClick),
    ) {
        AsyncImage(
            model = game.coverUrl,
            contentDescription = game.title,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxWidth().height(96.dp),
        )
        Box(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(8.dp),
        ) {
            Text(
                text = game.title,
                color = UGColors.TextPrimary,
                style = UGType.Caption,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, widthDp = 180, heightDp = 130)
@Composable
private fun WideGameCardPreview() {
    UGamesTheme {
        WideGameCard(
            game = Game(
                appId = 1, title = "Drift King",
                rating = 4.5f, ratingCount = 12,
                coverUrl = "", iconUrl = "",
                categories = listOf("Racing"), developer = "studio",
                mainColor = "#FFC700",
            ),
            onClick = {},
            modifier = Modifier.padding(12.dp),
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `cd android && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/games/yandex/wrap/ui/components/GameCard.kt
git commit -m "feat(android): add WideGameCard"
```

---

### Task 13: Android — SquareGameCard

**Files:**
- Modify: `android/app/src/main/kotlin/games/yandex/wrap/ui/components/GameCard.kt`

- [ ] **Step 1: Append SquareGameCard at EOF**

```kotlin
/**
 * Square 130×130 icon card for per-genre rows. Title under cover.
 * Uses iconUrl primarily (icons are square in feed; covers are 16:9).
 */
@Composable
fun SquareGameCard(
    game: Game,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val haloColor = parseHexColor(game.iconMainColor ?: game.mainColor) ?: UGColors.Accent
    val placeholder = parseHexColor(game.iconMainColor ?: game.mainColor) ?: UGColors.Elevated
    Column(
        modifier = modifier.clickable(onClick = onClick),
    ) {
        Box(
            modifier = Modifier
                .size(130.dp)
                .shadow(
                    elevation = 12.dp,
                    shape = RoundedCornerShape(16.dp),
                    clip = false,
                    ambientColor = haloColor.copy(alpha = UGColors.HaloAlpha),
                    spotColor = haloColor.copy(alpha = UGColors.HaloAlpha),
                )
                .clip(RoundedCornerShape(16.dp))
                .background(placeholder)
                .border(
                    width = 1.dp,
                    color = haloColor.copy(alpha = UGColors.HaloBorderAlpha),
                    shape = RoundedCornerShape(16.dp),
                ),
        ) {
            AsyncImage(
                model = game.iconUrl.ifEmpty { game.coverUrl },
                contentDescription = game.title,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(130.dp),
            )
        }
        Spacer(Modifier.height(6.dp))
        Text(
            text = game.title,
            color = UGColors.TextPrimary,
            style = UGType.BodyS,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(horizontal = 2.dp),
        )
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, widthDp = 160, heightDp = 180)
@Composable
private fun SquareGameCardPreview() {
    UGamesTheme {
        SquareGameCard(
            game = Game(
                appId = 1, title = "Lily's Tea",
                rating = 4.8f, ratingCount = 24,
                coverUrl = "", iconUrl = "",
                categories = listOf("Casual"), developer = "studio",
                mainColor = "#FF7EB9",
                iconMainColor = "#FF7EB9",
            ),
            onClick = {},
            modifier = Modifier.padding(12.dp),
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `cd android && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/games/yandex/wrap/ui/components/GameCard.kt
git commit -m "feat(android): add SquareGameCard"
```

---

### Task 14: Android — HeroSection (stub, без видео)

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/components/Hero.kt`

- [ ] **Step 1: Create HeroSection — image-only stub**

```kotlin
package games.yandex.wrap.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import games.yandex.wrap.catalog.Game
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType
import games.yandex.wrap.ui.theme.UGamesTheme
import games.yandex.wrap.ui.theme.parseHexColor

/**
 * Editorial hero card for Home. Phase 1 STUB: image background + gradient.
 * Phase 2 will add video autoplay through media3 ExoPlayer when game.videoUrl
 * is non-null.
 *
 * 300dp tall, fills width.
 */
@Composable
fun HeroSection(
    game: Game,
    onPlay: () -> Unit,
    onFavorite: () -> Unit,
    onShare: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val haloColor = parseHexColor(game.mainColor) ?: UGColors.Accent
    val placeholder = parseHexColor(game.mainColor) ?: UGColors.Elevated

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(300.dp)
            .shadow(
                elevation = 20.dp,
                shape = RoundedCornerShape(22.dp),
                clip = false,
                ambientColor = haloColor.copy(alpha = UGColors.HaloAlpha),
                spotColor = haloColor.copy(alpha = UGColors.HaloAlpha),
            )
            .clip(RoundedCornerShape(22.dp))
            .background(placeholder)
            .border(
                width = 1.dp,
                color = haloColor.copy(alpha = UGColors.HaloBorderAlpha),
                shape = RoundedCornerShape(22.dp),
            ),
    ) {
        AsyncImage(
            model = game.coverUrl,
            contentDescription = game.title,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        0.35f to Color.Transparent,
                        1.0f to Color.Black.copy(alpha = 0.85f),
                    )
                ),
        )
        Row(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(UGColors.Accent.copy(alpha = 0.18f))
                    .padding(horizontal = 10.dp, vertical = 5.dp),
            ) {
                Text(
                    text = "✦ FEATURED TODAY",
                    color = UGColors.Accent,
                    style = UGType.Caption,
                )
            }
            Spacer(Modifier.weight(1f))
            HeroIconButton(icon = Icons.Filled.FavoriteBorder, contentDescription = "Save", onClick = onFavorite)
            Spacer(Modifier.width(8.dp))
            HeroIconButton(icon = Icons.Filled.Share, contentDescription = "Share", onClick = onShare)
        }
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .padding(18.dp),
        ) {
            val chips = listOfNotNull(
                if (game.rating > 0f) "★ %.1f".format(game.rating) else null,
                if (game.ratingCount > 0) "${game.ratingCount} ratings" else null,
                game.categories.firstOrNull(),
            )
            if (chips.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    chips.forEach { chip ->
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(999.dp))
                                .background(Color.White.copy(alpha = 0.08f))
                                .padding(horizontal = 9.dp, vertical = 5.dp),
                        ) {
                            Text(text = chip, color = UGColors.TextSecondary, style = UGType.Caption)
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
            }
            Text(
                text = game.title,
                color = UGColors.TextPrimary,
                style = UGType.Display,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(14.dp))
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(UGColors.AccentGradient)
                    .clickable(onClick = onPlay)
                    .padding(horizontal = 22.dp, vertical = 11.dp),
            ) {
                Text(text = "▶ Play now", color = Color.Black, style = UGType.BodyS)
            }
        }
    }
}

@Composable
private fun HeroIconButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(32.dp)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.5f))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = UGColors.TextPrimary,
            modifier = Modifier.size(16.dp),
        )
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, widthDp = 360, heightDp = 340)
@Composable
private fun HeroSectionPreview() {
    UGamesTheme {
        HeroSection(
            game = Game(
                appId = 1,
                title = "Block Puzzle: Falling Shapes",
                rating = 4.9f, ratingCount = 39,
                coverUrl = "", iconUrl = "",
                categories = listOf("Puzzle"), developer = "studio",
                mainColor = "#41B4F6",
            ),
            onPlay = {}, onFavorite = {}, onShare = {},
            modifier = Modifier.padding(14.dp),
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `cd android && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/games/yandex/wrap/ui/components/Hero.kt
git commit -m "feat(android): add HeroSection (image stub, video in phase 2)"
```

---

### Task 15: Android — StoryCard

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/components/StoryCard.kt`

- [ ] **Step 1: Create StoryCard**

```kotlin
package games.yandex.wrap.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import games.yandex.wrap.catalog.Game
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType
import games.yandex.wrap.ui.theme.UGamesTheme
import games.yandex.wrap.ui.theme.parseHexColor

/**
 * Editorial Spotlight card. 22-radius, 160dp, gradient bg from the first
 * cover's mainColor, three smaller covers stacked top-right with tilt,
 * eyebrow + title bottom-left.
 */
@Composable
fun StoryCard(
    title: String,
    subtitle: String,
    games: List<Game>,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val anchor = parseHexColor(games.firstOrNull()?.mainColor) ?: UGColors.Accent
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(160.dp)
            .shadow(
                elevation = 20.dp,
                shape = RoundedCornerShape(22.dp),
                clip = false,
                ambientColor = anchor.copy(alpha = UGColors.HaloAlpha),
                spotColor = anchor.copy(alpha = UGColors.HaloAlpha),
            )
            .clip(RoundedCornerShape(22.dp))
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        anchor.copy(alpha = 0.55f),
                        Color(0xFF0A0418),
                    ),
                )
            )
            .border(
                width = 1.dp,
                color = anchor.copy(alpha = UGColors.HaloBorderAlpha),
                shape = RoundedCornerShape(22.dp),
            )
            .clickable(onClick = onClick),
    ) {
        val sample = games.take(3)
        sample.forEachIndexed { index, g ->
            val placeholder = parseHexColor(g.mainColor) ?: UGColors.Elevated
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 54.dp)
                    .offset(x = (-14 - index * 8).dp)
                    .rotate(degrees = (-8 + index * 8).toFloat())
                    .size(42.dp)
                    .shadow(elevation = 6.dp, shape = RoundedCornerShape(10.dp), clip = false)
                    .clip(RoundedCornerShape(10.dp))
                    .background(placeholder),
            ) {
                AsyncImage(
                    model = g.iconUrl.ifEmpty { g.coverUrl },
                    contentDescription = g.title,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        0.5f to Color.Transparent,
                        1.0f to Color.Black.copy(alpha = 0.6f),
                    )
                ),
        )
        Column(
            modifier = Modifier.align(Alignment.BottomStart).padding(18.dp),
        ) {
            Text(text = subtitle, color = UGColors.TextSecondary, style = UGType.Label)
            Text(
                text = title,
                color = UGColors.TextPrimary,
                style = UGType.TitleL,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, widthDp = 360, heightDp = 200)
@Composable
private fun StoryCardPreview() {
    UGamesTheme {
        StoryCard(
            title = "5 brain-bending puzzles to try this week",
            subtitle = "SPOTLIGHT · ISSUE #04",
            games = listOf(
                Game(1, "A", 0f, 0, "", "", emptyList(), "", "#9B6CFF", "#9B6CFF"),
                Game(2, "B", 0f, 0, "", "", emptyList(), "", "#43E890", "#43E890"),
                Game(3, "C", 0f, 0, "", "", emptyList(), "", "#FF7EB9", "#FF7EB9"),
            ),
            onClick = {},
            modifier = Modifier.padding(14.dp),
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `cd android && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/games/yandex/wrap/ui/components/StoryCard.kt
git commit -m "feat(android): add StoryCard editorial component"
```

---

### Task 16: Android — GenreChipRow

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/components/GenreChipRow.kt`

- [ ] **Step 1: Create GenreChipRow**

```kotlin
package games.yandex.wrap.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType
import games.yandex.wrap.ui.theme.UGamesTheme

/**
 * Horizontal scroll of genre chips. The first chip is always "All" (passes
 * null as the selected category).
 */
@Composable
fun GenreChipRow(
    genres: List<String>,
    selected: String?,
    onSelect: (String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    val items = listOf<String?>(null) + genres
    LazyRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = PaddingValues(horizontal = 14.dp),
    ) {
        items(items) { genre ->
            val active = genre == selected
            val label = genre ?: "All"
            val bg = if (active) UGColors.Accent else UGColors.Surface
            val fg = if (active) UGColors.Bg0 else UGColors.TextSecondary
            val borderColor = if (active) UGColors.Accent else UGColors.Divider
            val shadowMod = if (active) {
                Modifier.shadow(
                    elevation = 8.dp,
                    shape = RoundedCornerShape(999.dp),
                    clip = false,
                    ambientColor = UGColors.Accent.copy(alpha = 0.4f),
                    spotColor = UGColors.Accent.copy(alpha = 0.4f),
                )
            } else Modifier
            Text(
                text = label,
                style = UGType.BodyS,
                color = fg,
                modifier = Modifier
                    .then(shadowMod)
                    .clip(RoundedCornerShape(999.dp))
                    .background(bg)
                    .border(1.dp, borderColor, RoundedCornerShape(999.dp))
                    .clickable { onSelect(genre) }
                    .padding(horizontal = 14.dp, vertical = 8.dp),
            )
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, widthDp = 400, heightDp = 60)
@Composable
private fun GenreChipRowPreview() {
    UGamesTheme {
        GenreChipRow(
            genres = listOf("Action", "Puzzle", "Racing", "Casual", "Word"),
            selected = "Puzzle",
            onSelect = {},
            modifier = Modifier.padding(vertical = 8.dp),
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `cd android && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/games/yandex/wrap/ui/components/GenreChipRow.kt
git commit -m "feat(android): add GenreChipRow"
```

---

### Task 17: Android — FloatingTabBar

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/components/FloatingTabBar.kt`

- [ ] **Step 1: Create FloatingTabBar (semi-transparent fallback only — real RenderEffect blur deferred to Phase 5)**

```kotlin
package games.yandex.wrap.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Home
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import games.yandex.wrap.ui.theme.UGColors
import games.yandex.wrap.ui.theme.UGType
import games.yandex.wrap.ui.theme.UGamesTheme

data class UGTab(
    val key: String,
    val label: String,
    val icon: ImageVector,
)

/**
 * Floating glass tab bar — pill-shaped, 24dp horizontal margin, ~62dp tall.
 * Phase 1 uses semi-transparent surface (UGColors.GlassFallback). Real
 * RenderEffect blur lands in Phase 5 polish.
 */
@Composable
fun FloatingTabBar(
    tabs: List<UGTab>,
    selectedKey: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 14.dp)
            .shadow(20.dp, RoundedCornerShape(28.dp), clip = false)
            .clip(RoundedCornerShape(28.dp))
            .background(UGColors.GlassFallback)
            .border(1.dp, UGColors.Divider, RoundedCornerShape(28.dp))
            .height(62.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        tabs.forEach { tab ->
            val active = tab.key == selectedKey
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .clickable { onSelect(tab.key) }
                    .padding(horizontal = 12.dp, vertical = 6.dp),
            ) {
                Icon(
                    imageVector = tab.icon,
                    contentDescription = tab.label,
                    tint = if (active) UGColors.Accent else UGColors.TextMuted,
                    modifier = Modifier
                        .padding(bottom = 2.dp)
                        .size(22.dp),
                )
                Text(
                    text = tab.label,
                    color = if (active) UGColors.Accent else UGColors.TextMuted,
                    style = UGType.Caption,
                )
            }
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, widthDp = 400, heightDp = 110)
@Composable
private fun FloatingTabBarPreview() {
    UGamesTheme {
        FloatingTabBar(
            tabs = listOf(
                UGTab("home", "Home", Icons.Filled.Home),
                UGTab("browse", "Browse", Icons.Filled.GridView),
                UGTab("favorites", "Favorites", Icons.Filled.Favorite),
                UGTab("profile", "Profile", Icons.Filled.AccountCircle),
            ),
            selectedKey = "home",
            onSelect = {},
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `cd android && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/games/yandex/wrap/ui/components/FloatingTabBar.kt
git commit -m "feat(android): add FloatingTabBar (glass fallback in phase 1)"
```

---

### Task 18: Android — TabContainer + MainActivity wiring

**Files:**
- Create: `android/app/src/main/kotlin/games/yandex/wrap/ui/TabContainer.kt`
- Modify: `android/app/src/main/kotlin/games/yandex/wrap/MainActivity.kt`
- Modify: `android/app/src/main/kotlin/games/yandex/wrap/ui/CatalogScreen.kt` (one-line padding change)

- [ ] **Step 1: Create TabContainer**

```kotlin
package games.yandex.wrap.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Home
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import games.yandex.wrap.ui.components.EmptyState
import games.yandex.wrap.ui.components.FloatingTabBar
import games.yandex.wrap.ui.components.UGTab

/**
 * Phase 1 tab container. Home renders the existing CatalogScreen (passed in
 * via the [home] slot), other tabs are EmptyState placeholders. The bar is
 * hidden when [hideBar] is true (e.g., when caller pushes Game/Auth/Logs
 * over the container).
 */
@Composable
fun TabContainer(
    hideBar: Boolean,
    home: @Composable () -> Unit,
) {
    var selected by remember { mutableStateOf("home") }
    Box(modifier = Modifier.fillMaxSize()) {
        when (selected) {
            "home" -> home()
            "browse" -> EmptyState(
                icon = Icons.Filled.GridView,
                title = "Browse — coming soon",
                body = "Genre filters and sort will land here.",
            )
            "favorites" -> EmptyState(
                icon = Icons.Filled.Favorite,
                title = "Favorites — coming soon",
                body = "Saved games will live here.",
            )
            "profile" -> EmptyState(
                icon = Icons.Filled.AccountCircle,
                title = "Profile — coming soon",
                body = "Sign in / Plus / Logs.",
            )
        }
        if (!hideBar) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.BottomCenter,
            ) {
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

- [ ] **Step 2: Wire TabContainer into MainActivity**

In `MainActivity.kt` (after Task 4 it already uses `UGamesTheme {}`), wrap the `Route.Catalog` branch only. Find:

```kotlin
                        Route.Catalog -> CatalogScreen(
                            viewModel = catalogVm,
                            onGameClick = { game ->
                                catalogVm.recordGameOpen(game)
                                route = Route.Game(game.appId, game.title)
                            },
                            onLoginClick = { route = Route.Auth },
                            onLogsRequest = { route = Route.Logs },
                        )
```

Replace with:

```kotlin
                        Route.Catalog -> TabContainer(hideBar = false) {
                            CatalogScreen(
                                viewModel = catalogVm,
                                onGameClick = { game ->
                                    catalogVm.recordGameOpen(game)
                                    route = Route.Game(game.appId, game.title)
                                },
                                onLoginClick = { route = Route.Auth },
                                onLogsRequest = { route = Route.Logs },
                            )
                        }
```

Add at the top of MainActivity.kt (with the other `import games.yandex.wrap.ui.*` imports):

```kotlin
import games.yandex.wrap.ui.TabContainer
```

- [ ] **Step 3: Add bottom padding to CatalogScreen so floating bar doesn't cover content**

Edit `android/app/src/main/kotlin/games/yandex/wrap/ui/CatalogScreen.kt`. In the `LazyVerticalGrid` block (around line 191), find:

```kotlin
                        contentPadding = PaddingValues(12.dp),
```

Replace with:

```kotlin
                        contentPadding = PaddingValues(start = 12.dp, end = 12.dp, top = 12.dp, bottom = 96.dp),
```

(Bottom 96dp = 62dp bar + 14dp side padding + 20dp safe-area buffer.)

- [ ] **Step 4: Build and run**

Run: `cd android && ./gradlew :app:assembleDebug`
Expected: BUILD SUCCESSFUL.

Manual verification on device/emulator:
- Home tab: existing catalog renders, scrollable, last row visible above floating tab bar.
- Browse / Favorites / Profile tabs: each shows the corresponding "Coming soon" empty state.
- Tap a game → game launches in WebView; tab bar hidden in-game.
- Back from game → returns to Home tab, bar visible.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/games/yandex/wrap/ui/TabContainer.kt android/app/src/main/kotlin/games/yandex/wrap/MainActivity.kt android/app/src/main/kotlin/games/yandex/wrap/ui/CatalogScreen.kt
git commit -m "feat(android): wrap catalog in 4-tab scaffold (Home only, others stub)"
```

---

### Task 19: iOS — Hex extension

**Files:**
- Create: `ios/UGames/Theme/Hex.swift`

- [ ] **Step 1: Create Color extension**

```swift
import SwiftUI

/// Parse a "#RRGGBB" or "#AARRGGBB" hex string into a SwiftUI Color.
/// Returns nil for blank, malformed, or wrong-length strings — callers
/// should fall back to a default (e.g. UGColor.surface).
extension Color {
    init?(hex: String?) {
        guard let raw = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let cleaned = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        guard let value = UInt64(cleaned, radix: 16) else { return nil }
        switch cleaned.count {
        case 6:
            let r = Double((value >> 16) & 0xFF) / 255.0
            let g = Double((value >> 8) & 0xFF) / 255.0
            let b = Double(value & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b)
        case 8:
            let a = Double((value >> 24) & 0xFF) / 255.0
            let r = Double((value >> 16) & 0xFF) / 255.0
            let g = Double((value >> 8) & 0xFF) / 255.0
            let b = Double(value & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b, opacity: a)
        default:
            return nil
        }
    }
}
```

- [ ] **Step 2: Verify ios builds**

```bash
cd ios && xcodegen generate && xcodebuild -project UGames.xcodeproj -scheme UGames -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`.

If `xcodegen` is not installed: `brew install xcodegen`.

- [ ] **Step 3: Commit**

```bash
git add ios/UGames/Theme/Hex.swift
git commit -m "feat(ios): add Color(hex:) extension for mainColor parsing"
```

---

### Task 20: iOS — Theme tokens

**Files:**
- Create: `ios/UGames/Theme/Theme.swift`

- [ ] **Step 1: Create UGColor enum and UGFont enum**

```swift
import SwiftUI

/// U-Games premium theme tokens — names match the spec
/// (docs/superpowers/specs/2026-05-05-ui-ux-redesign-design.md).
enum UGColor {
    static let bg0 = Color(red: 0, green: 0, blue: 0)
    static let surface = Color(red: 0x0D / 255.0, green: 0x0D / 255.0, blue: 0x10 / 255.0)
    static let elevated = Color(red: 0x1A / 255.0, green: 0x1A / 255.0, blue: 0x20 / 255.0)
    static let divider = Color(red: 0x1F / 255.0, green: 0x1F / 255.0, blue: 0x22 / 255.0)

    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0xC8 / 255.0, green: 0xC8 / 255.0, blue: 0xD0 / 255.0)
    static let textMuted = Color(red: 0x7A / 255.0, green: 0x7A / 255.0, blue: 0x82 / 255.0)

    static let accent = Color(red: 1.0, green: 0xC7 / 255.0, blue: 0)
    static let accentEnd = Color(red: 1.0, green: 0x7E / 255.0, blue: 0)
    static let danger = Color(red: 1.0, green: 0x4D / 255.0, blue: 0x6A / 255.0)

    static let glassFallback = Color(red: 0x14 / 255.0, green: 0x14 / 255.0, blue: 0x18 / 255.0).opacity(0.85)

    static let haloAlpha: Double = 0.35
    static let haloBorderAlpha: Double = 0.18
}

extension LinearGradient {
    static var ugAccent: LinearGradient {
        LinearGradient(
            colors: [UGColor.accent, UGColor.accentEnd],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

/// Typography tokens. Sizes from the spec table.
enum UGFont {
    static let displayXL = Font.system(size: 34, weight: .black)
    static let display = Font.system(size: 30, weight: .black)
    static let titleL = Font.system(size: 24, weight: .heavy)
    static let titleM = Font.system(size: 18, weight: .heavy)
    static let body = Font.system(size: 15, weight: .regular)
    static let bodyS = Font.system(size: 13, weight: .medium)
    static let label = Font.system(size: 11, weight: .semibold)
    static let caption = Font.system(size: 10, weight: .bold)
}
```

- [ ] **Step 2: Build**

```bash
cd ios && xcodegen generate && xcodebuild -project UGames.xcodeproj -scheme UGames -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/UGames/Theme/Theme.swift
git commit -m "feat(ios): add UGColor and UGFont tokens"
```

---

### Task 21: iOS — Game model fields

**Files:**
- Modify: `ios/UGames/Catalog/Game.swift`

- [ ] **Step 1: Read current Game.swift**

Run: `cat ios/UGames/Catalog/Game.swift`

- [ ] **Step 2: Add three new fields**

Inside the `struct Game`, add these stored properties at the end of the field list:

```swift
    var mainColor: String?
    var iconMainColor: String?
    var videoUrl: String?
```

If there is a memberwise init synthesized automatically — the new fields automatically pick up `nil`-default behaviour as long as you give them `?` types (Swift won't synthesize default-`nil` though; you must call sites adapt or you must add a custom init).

If `Game` has no custom init, leave it alone — Swift's synthesized memberwise init now requires the new params, which we'll handle in Task 22 (the only caller will be `CatalogService` and that already constructs `Game` from a JSON dict so it'll be updated together).

If the struct has a custom init, add to its parameter list:

```swift
        mainColor: String? = nil,
        iconMainColor: String? = nil,
        videoUrl: String? = nil,
```

and assign:

```swift
        self.mainColor = mainColor
        self.iconMainColor = iconMainColor
        self.videoUrl = videoUrl
```

- [ ] **Step 3: Build (might need Task 22 done first if Game lacks default-nil and other call sites exist)**

```bash
cd ios && xcodegen generate && xcodebuild -project UGames.xcodeproj -scheme UGames -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
```

If build fails because of missing args at non-CatalogService call sites, take note and proceed to Task 22 — they'll be aligned together.

Expected (after Task 22): BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add ios/UGames/Catalog/Game.swift
git commit -m "feat(ios): extend Game with mainColor, iconMainColor, videoUrl"
```

---

### Task 22: iOS — CatalogService parsing

**Files:**
- Modify: `ios/UGames/Catalog/CatalogService.swift`

- [ ] **Step 1: Locate the JSON-to-Game parsing**

Run: `grep -n "media\|cover\|prefix-url" ios/UGames/Catalog/CatalogService.swift`

This shows where covers/icons are pulled. Find the function that maps a JSON dict to `Game` (it'll be the iOS twin of `itemToGame`).

- [ ] **Step 2: Add mainColor, iconMainColor, videoUrl extraction**

In that function, alongside cover/icon-prefix extraction, add:

```swift
let coverObj = (item["media"] as? [String: Any])?["cover"] as? [String: Any]
let iconObj = (item["media"] as? [String: Any])?["icon"] as? [String: Any]
let mainColor = coverObj?["mainColor"] as? String
let iconMainColor = iconObj?["mainColor"] as? String
let videos = (item["media"] as? [String: Any])?["videos"] as? [[String: Any]]
let videoUrl = videos?.first?["mp4StreamUrl"] as? String
```

Pass these to the `Game(...)` constructor where it's built — extending the call site with `mainColor: mainColor, iconMainColor: iconMainColor, videoUrl: videoUrl` (named args). Keep existing field assignments unchanged.

- [ ] **Step 3: Build**

```bash
cd ios && xcodegen generate && xcodebuild -project UGames.xcodeproj -scheme UGames -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add ios/UGames/Catalog/CatalogService.swift
git commit -m "feat(ios): parse mainColor, iconMainColor, videoUrl from feed"
```

---

### Task 23: iOS — Skeleton component

**Files:**
- Create: `ios/UGames/Components/Skeleton.swift`

- [ ] **Step 1: Create Skeleton with shimmer**

```swift
import SwiftUI

/// Animated shimmer placeholder. Replaces ProgressView spinners. Animates a
/// left-to-right gradient sweep at 1.4s on infinite repeat.
struct Skeleton: View {
    var cornerRadius: CGFloat = 12

    @State private var phase: CGFloat = -0.3

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: UGColor.elevated, location: 0),
                        .init(color: Color(red: 0x22 / 255.0, green: 0x22 / 255.0, blue: 0x2A / 255.0), location: max(0, min(1, phase + 0.3))),
                        .init(color: UGColor.elevated, location: max(0, min(1, phase + 0.6))),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
    }
}

#Preview(traits: .fixedLayout(width: 360, height: 120)) {
    ZStack {
        Color.black.ignoresSafeArea()
        Skeleton()
            .padding()
            .frame(height: 120)
    }
}
```

- [ ] **Step 2: Build**

```bash
cd ios && xcodegen generate && xcodebuild -project UGames.xcodeproj -scheme UGames -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/UGames/Components/Skeleton.swift
git commit -m "feat(ios): add Skeleton shimmer component"
```

---

### Task 24: iOS — EmptyState component

**Files:**
- Create: `ios/UGames/Components/EmptyState.swift`

- [ ] **Step 1: Create EmptyState (note: rename body→message to avoid View.body collision)**

```swift
import SwiftUI

struct EmptyState: View {
    let systemIcon: String
    let title: String
    var message: String? = nil
    var ctaLabel: String? = nil
    var onCta: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: systemIcon)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(UGColor.textMuted)
                .padding(.bottom, 14)
            Text(title)
                .font(UGFont.titleM)
                .foregroundColor(UGColor.textPrimary)
            if let message, !message.isEmpty {
                Text(message)
                    .font(UGFont.bodyS)
                    .foregroundColor(UGColor.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            if let ctaLabel, let onCta {
                Button(action: onCta) {
                    Text(ctaLabel)
                        .font(UGFont.bodyS)
                        .foregroundColor(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(LinearGradient.ugAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
    }
}

#Preview(traits: .fixedLayout(width: 360, height: 320)) {
    ZStack {
        Color.black.ignoresSafeArea()
        EmptyState(
            systemIcon: "heart",
            title: "No favorites yet",
            message: "Tap ♥ on any game to save it.",
            ctaLabel: "Browse games",
            onCta: {}
        )
    }
}
```

- [ ] **Step 2: Build**

```bash
cd ios && xcodegen generate && xcodebuild -project UGames.xcodeproj -scheme UGames -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/UGames/Components/EmptyState.swift
git commit -m "feat(ios): add EmptyState component"
```

---

### Task 25: iOS — ErrorState component

**Files:**
- Create: `ios/UGames/Components/ErrorState.swift`

- [ ] **Step 1: Create ErrorState**

```swift
import SwiftUI

struct ErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(UGColor.textMuted)
                .padding(.bottom, 14)
            Text("Couldn't load")
                .font(UGFont.titleM)
                .foregroundColor(UGColor.textPrimary)
            Text(message)
                .font(UGFont.bodyS)
                .foregroundColor(UGColor.textMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Button(action: onRetry) {
                Text("Try again")
                    .font(UGFont.bodyS)
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(LinearGradient.ugAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
    }
}

#Preview(traits: .fixedLayout(width: 360, height: 320)) {
    ZStack {
        Color.black.ignoresSafeArea()
        ErrorState(message: "Check your connection and try again.", onRetry: {})
    }
}
```

- [ ] **Step 2: Build**

```bash
cd ios && xcodegen generate && xcodebuild -project UGames.xcodeproj -scheme UGames -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/UGames/Components/ErrorState.swift
git commit -m "feat(ios): add ErrorState component"
```

---

### Task 26: iOS — TileGameCard

**Files:**
- Create: `ios/UGames/Components/GameCard.swift`

- [ ] **Step 1: Create GameCard.swift with TileGameCard**

```swift
import SwiftUI

/// Tile card for grids (Browse / Favorites / Similar).
struct TileGameCard: View {
    let game: Game
    let isFavorite: Bool
    let onTap: () -> Void
    let onFavoriteToggle: () -> Void

    private var halo: Color { Color(hex: game.mainColor) ?? UGColor.accent }
    private var placeholder: Color { Color(hex: game.mainColor) ?? UGColor.elevated }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                placeholder
                    .aspectRatio(16.0/10.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        AsyncImage(url: URL(string: game.coverUrl)) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Color.clear
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(halo.opacity(UGColor.haloBorderAlpha)))
                    .shadow(color: halo.opacity(UGColor.haloAlpha), radius: 14, x: 0, y: 12)

                Button(action: onFavoriteToggle) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isFavorite ? UGColor.danger : UGColor.textPrimary)
                        .frame(width: 30, height: 30)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
                .padding(8)

                if game.ratingCount > 0 {
                    HStack {
                        Text(String(format: "★ %.1f", game.rating))
                            .font(UGFont.caption)
                            .foregroundColor(UGColor.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Capsule())
                        Spacer()
                    }
                    .padding(8)
                    .frame(maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            Text(game.title)
                .font(UGFont.bodyS)
                .foregroundColor(UGColor.textPrimary)
                .lineLimit(2)
            let meta = [
                game.categories.first,
                game.ratingCount > 0 ? "\(game.ratingCount) ratings" : nil,
            ].compactMap { $0 }.joined(separator: " · ")
            if !meta.isEmpty {
                Text(meta)
                    .font(UGFont.caption)
                    .foregroundColor(UGColor.textMuted)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

#Preview(traits: .fixedLayout(width: 200, height: 220)) {
    ZStack {
        Color.black.ignoresSafeArea()
        TileGameCard(
            game: Game(
                appId: 1, title: "Block Puzzle: Falling Shapes",
                rating: 4.9, ratingCount: 39,
                coverUrl: "", iconUrl: "",
                categories: ["Puzzle"], developer: "studio",
                mainColor: "#41B4F6"
            ),
            isFavorite: true,
            onTap: {}, onFavoriteToggle: {}
        )
        .padding(12)
    }
}
```

(If your `Game` init differs in field names/order, adjust the preview's literal — runtime code uses named args so it's stable.)

- [ ] **Step 2: Build**

```bash
cd ios && xcodegen generate && xcodebuild -project UGames.xcodeproj -scheme UGames -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/UGames/Components/GameCard.swift
git commit -m "feat(ios): add TileGameCard with mainColor halo"
```

---

### Task 27: iOS — WideGameCard

**Files:**
- Modify: `ios/UGames/Components/GameCard.swift`

- [ ] **Step 1: Append WideGameCard struct (and a separate `#Preview`)**

```swift
/// Wide card (140×96) for Continue / Trending / Favorites rows on Home.
struct WideGameCard: View {
    let game: Game
    let onTap: () -> Void

    private var halo: Color { Color(hex: game.mainColor) ?? UGColor.accent }
    private var placeholder: Color { Color(hex: game.mainColor) ?? UGColor.elevated }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            placeholder
            AsyncImage(url: URL(string: game.coverUrl)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: Color.clear
                }
            }
            Text(game.title)
                .font(UGFont.caption)
                .foregroundColor(UGColor.textPrimary)
                .lineLimit(1)
                .padding(8)
                .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 2)
        }
        .frame(width: 140, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(halo.opacity(UGColor.haloBorderAlpha)))
        .shadow(color: halo.opacity(UGColor.haloAlpha), radius: 14, x: 0, y: 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

#Preview("Wide", traits: .fixedLayout(width: 180, height: 130)) {
    ZStack {
        Color.black.ignoresSafeArea()
        WideGameCard(
            game: Game(
                appId: 2, title: "Drift King",
                rating: 4.5, ratingCount: 12,
                coverUrl: "", iconUrl: "",
                categories: ["Racing"], developer: "studio",
                mainColor: "#FFC700"
            ),
            onTap: {}
        )
    }
}
```

- [ ] **Step 2: Build**

```bash
cd ios && xcodegen generate && xcodebuild -project UGames.xcodeproj -scheme UGames -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/UGames/Components/GameCard.swift
git commit -m "feat(ios): add WideGameCard"
```

---

### Task 28: iOS — SquareGameCard

**Files:**
- Modify: `ios/UGames/Components/GameCard.swift`

- [ ] **Step 1: Append SquareGameCard struct**

```swift
/// 130×130 icon card with title underneath. Per-genre rows on Home.
struct SquareGameCard: View {
    let game: Game
    let onTap: () -> Void

    private var halo: Color {
        Color(hex: game.iconMainColor ?? game.mainColor) ?? UGColor.accent
    }
    private var placeholder: Color {
        Color(hex: game.iconMainColor ?? game.mainColor) ?? UGColor.elevated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                placeholder
                AsyncImage(url: URL(string: game.iconUrl.isEmpty ? game.coverUrl : game.iconUrl)) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.clear
                    }
                }
            }
            .frame(width: 130, height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(halo.opacity(UGColor.haloBorderAlpha)))
            .shadow(color: halo.opacity(UGColor.haloAlpha), radius: 14, x: 0, y: 12)
            Text(game.title)
                .font(UGFont.bodyS)
                .foregroundColor(UGColor.textPrimary)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

#Preview("Square", traits: .fixedLayout(width: 160, height: 180)) {
    ZStack {
        Color.black.ignoresSafeArea()
        SquareGameCard(
            game: Game(
                appId: 3, title: "Lily's Tea",
                rating: 4.8, ratingCount: 24,
                coverUrl: "", iconUrl: "",
                categories: ["Casual"], developer: "studio",
                mainColor: "#FF7EB9",
                iconMainColor: "#FF7EB9"
            ),
            onTap: {}
        )
    }
}
```

- [ ] **Step 2: Build**

```bash
cd ios && xcodegen generate && xcodebuild -project UGames.xcodeproj -scheme UGames -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/UGames/Components/GameCard.swift
git commit -m "feat(ios): add SquareGameCard"
```

---

### Task 29: iOS — HeroSection (stub)

**Files:**
- Create: `ios/UGames/Components/Hero.swift`

- [ ] **Step 1: Create HeroSection — image-only stub**

```swift
import SwiftUI

/// Editorial Hero card for Home. Phase 1 STUB: image background + gradient.
/// Phase 2 will autoplay videoUrl through AVPlayerLayer when present.
struct HeroSection: View {
    let game: Game
    let onPlay: () -> Void
    let onFavorite: () -> Void
    let onShare: () -> Void

    private var halo: Color { Color(hex: game.mainColor) ?? UGColor.accent }
    private var placeholder: Color { Color(hex: game.mainColor) ?? UGColor.elevated }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            placeholder
            AsyncImage(url: URL(string: game.coverUrl)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: Color.clear
                }
            }
            LinearGradient(
                stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.85), location: 1.0)],
                startPoint: .top, endPoint: .bottom
            )
            VStack { topRow; Spacer() }
            bottomBlock
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(halo.opacity(UGColor.haloBorderAlpha)))
        .shadow(color: halo.opacity(UGColor.haloAlpha), radius: 20, x: 0, y: 14)
    }

    private var topRow: some View {
        HStack {
            Text("✦ FEATURED TODAY")
                .font(UGFont.caption)
                .foregroundColor(UGColor.accent)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(UGColor.accent.opacity(0.18))
                .clipShape(Capsule())
            Spacer()
            heroIcon("heart", action: onFavorite)
            heroIcon("square.and.arrow.up", action: onShare)
        }
        .padding(14)
    }

    @ViewBuilder
    private func heroIcon(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(UGColor.textPrimary)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .buttonStyle(.borderless)
    }

    private var bottomBlock: some View {
        let chips = [
            game.rating > 0 ? String(format: "★ %.1f", game.rating) : nil,
            game.ratingCount > 0 ? "\(game.ratingCount) ratings" : nil,
            game.categories.first,
        ].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 8) {
            if !chips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { c in
                        Text(c)
                            .font(UGFont.caption)
                            .foregroundColor(UGColor.textSecondary)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
            }
            Text(game.title)
                .font(UGFont.display)
                .foregroundColor(UGColor.textPrimary)
                .lineLimit(2)
            Button(action: onPlay) {
                Text("▶ Play now")
                    .font(UGFont.bodyS.weight(.heavy))
                    .foregroundColor(.black)
                    .padding(.horizontal, 22).padding(.vertical, 11)
                    .background(LinearGradient.ugAccent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.borderless)
        }
        .padding(18)
    }
}

#Preview(traits: .fixedLayout(width: 360, height: 320)) {
    ZStack {
        Color.black.ignoresSafeArea()
        HeroSection(
            game: Game(
                appId: 1, title: "Block Puzzle: Falling Shapes",
                rating: 4.9, ratingCount: 39,
                coverUrl: "", iconUrl: "",
                categories: ["Puzzle"], developer: "studio",
                mainColor: "#41B4F6"
            ),
            onPlay: {}, onFavorite: {}, onShare: {}
        )
        .padding(14)
    }
}
```

- [ ] **Step 2: Build**

```bash
cd ios && xcodegen generate && xcodebuild -project UGames.xcodeproj -scheme UGames -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/UGames/Components/Hero.swift
git commit -m "feat(ios): add HeroSection (image stub, video in phase 2)"
```

---

### Task 30: iOS — StoryCard

**Files:**
- Create: `ios/UGames/Components/StoryCard.swift`

- [ ] **Step 1: Create StoryCard**

```swift
import SwiftUI

struct StoryCard: View {
    let title: String
    let subtitle: String
    let games: [Game]
    let onTap: () -> Void

    private var anchor: Color { Color(hex: games.first?.mainColor) ?? UGColor.accent }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [anchor.opacity(0.55), Color(red: 0x0A/255.0, green: 0x04/255.0, blue: 0x18/255.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            stackedCovers
            LinearGradient(
                stops: [.init(color: .clear, location: 0.5), .init(color: .black.opacity(0.6), location: 1.0)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(UGFont.label)
                    .foregroundColor(UGColor.textSecondary)
                Text(title)
                    .font(UGFont.titleL)
                    .foregroundColor(UGColor.textPrimary)
                    .lineLimit(2)
            }
            .padding(18)
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(anchor.opacity(UGColor.haloBorderAlpha)))
        .shadow(color: anchor.opacity(UGColor.haloAlpha), radius: 20, x: 0, y: 14)
        .onTapGesture(perform: onTap)
    }

    private var stackedCovers: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(Array(games.prefix(3).enumerated()), id: \.element.appId) { idx, g in
                let placeholder = Color(hex: g.mainColor) ?? UGColor.elevated
                AsyncImage(url: URL(string: g.iconUrl.isEmpty ? g.coverUrl : g.iconUrl)) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: placeholder
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .rotationEffect(.degrees(Double(-8 + idx * 8)))
                .offset(x: CGFloat(-14 - idx * 8), y: 24)
                .shadow(radius: 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

#Preview(traits: .fixedLayout(width: 360, height: 200)) {
    ZStack {
        Color.black.ignoresSafeArea()
        StoryCard(
            title: "5 brain-bending puzzles to try this week",
            subtitle: "SPOTLIGHT · ISSUE #04",
            games: [
                Game(appId: 1, title: "A", rating: 0, ratingCount: 0, coverUrl: "", iconUrl: "", categories: [], developer: "", mainColor: "#9B6CFF"),
                Game(appId: 2, title: "B", rating: 0, ratingCount: 0, coverUrl: "", iconUrl: "", categories: [], developer: "", mainColor: "#43E890"),
                Game(appId: 3, title: "C", rating: 0, ratingCount: 0, coverUrl: "", iconUrl: "", categories: [], developer: "", mainColor: "#FF7EB9"),
            ],
            onTap: {}
        )
        .padding(14)
    }
}
```

- [ ] **Step 2: Build**

```bash
cd ios && xcodegen generate && xcodebuild -project UGames.xcodeproj -scheme UGames -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/UGames/Components/StoryCard.swift
git commit -m "feat(ios): add StoryCard editorial component"
```

---

### Task 31: iOS — GenreChipRow

**Files:**
- Create: `ios/UGames/Components/GenreChipRow.swift`

- [ ] **Step 1: Create GenreChipRow**

```swift
import SwiftUI

struct GenreChipRow: View {
    let genres: [String]
    let selected: String?
    let onSelect: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "All", value: nil)
                ForEach(genres, id: \.self) { g in chip(label: g, value: g) }
            }
            .padding(.horizontal, 14)
        }
    }

    private func chip(label: String, value: String?) -> some View {
        let active = (value == selected) || (value == nil && selected == nil)
        return Text(label)
            .font(UGFont.bodyS)
            .foregroundColor(active ? UGColor.bg0 : UGColor.textSecondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(active ? UGColor.accent : UGColor.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(active ? UGColor.accent : UGColor.divider))
            .shadow(color: active ? UGColor.accent.opacity(0.4) : .clear, radius: 8, x: 0, y: 0)
            .onTapGesture { onSelect(value) }
    }
}

#Preview(traits: .fixedLayout(width: 400, height: 60)) {
    ZStack {
        Color.black.ignoresSafeArea()
        GenreChipRow(
            genres: ["Action", "Puzzle", "Racing", "Casual", "Word"],
            selected: "Puzzle",
            onSelect: { _ in }
        )
    }
}
```

- [ ] **Step 2: Build**

```bash
cd ios && xcodegen generate && xcodebuild -project UGames.xcodeproj -scheme UGames -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/UGames/Components/GenreChipRow.swift
git commit -m "feat(ios): add GenreChipRow"
```

---

### Task 32: iOS — FloatingTabBar

**Files:**
- Create: `ios/UGames/Components/FloatingTabBar.swift`

- [ ] **Step 1: Create FloatingTabBar with .ultraThinMaterial blur**

```swift
import SwiftUI

struct UGTab: Identifiable, Equatable {
    let key: String
    let label: String
    let systemIcon: String
    var id: String { key }
}

struct FloatingTabBar: View {
    let tabs: [UGTab]
    let selectedKey: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                let active = tab.key == selectedKey
                VStack(spacing: 2) {
                    Image(systemName: tab.systemIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(active ? UGColor.accent : UGColor.textMuted)
                    Text(tab.label)
                        .font(UGFont.caption)
                        .foregroundColor(active ? UGColor.accent : UGColor.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture { onSelect(tab.key) }
            }
        }
        .frame(height: 62)
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial)
        .background(UGColor.surface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(UGColor.divider))
        .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 12)
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }
}

#Preview(traits: .fixedLayout(width: 400, height: 110)) {
    ZStack {
        Color.black.ignoresSafeArea()
        FloatingTabBar(
            tabs: [
                .init(key: "home", label: "Home", systemIcon: "house.fill"),
                .init(key: "browse", label: "Browse", systemIcon: "square.grid.2x2.fill"),
                .init(key: "favorites", label: "Favorites", systemIcon: "heart.fill"),
                .init(key: "profile", label: "Profile", systemIcon: "person.crop.circle.fill"),
            ],
            selectedKey: "home",
            onSelect: { _ in }
        )
    }
}
```

- [ ] **Step 2: Build**

```bash
cd ios && xcodegen generate && xcodebuild -project UGames.xcodeproj -scheme UGames -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/UGames/Components/FloatingTabBar.swift
git commit -m "feat(ios): add FloatingTabBar with ultraThinMaterial blur"
```

---

### Task 33: iOS — TabContainer + UGamesApp wiring

**Files:**
- Create: `ios/UGames/Views/TabContainer.swift`
- Modify: `ios/UGames/UGamesApp.swift`
- Modify: `ios/UGames/Views/CatalogView.swift`

- [ ] **Step 1: Create TabContainer**

```swift
import SwiftUI

/// Phase 1 tab container. Home renders the existing CatalogView via the
/// passed-in `home` ViewBuilder; other tabs are EmptyState("Coming soon").
/// `hideBar` is true while caller pushes Game/Auth/Logs above the container.
struct TabContainer<HomeContent: View>: View {
    let hideBar: Bool
    @ViewBuilder let home: () -> HomeContent

    @State private var selected: String = "home"

    private let tabs: [UGTab] = [
        .init(key: "home", label: "Home", systemIcon: "house.fill"),
        .init(key: "browse", label: "Browse", systemIcon: "square.grid.2x2.fill"),
        .init(key: "favorites", label: "Favorites", systemIcon: "heart.fill"),
        .init(key: "profile", label: "Profile", systemIcon: "person.crop.circle.fill"),
    ]

    var body: some View {
        ZStack {
            switch selected {
            case "home":
                home()
            case "browse":
                EmptyState(systemIcon: "square.grid.2x2", title: "Browse — coming soon", message: "Genre filters and sort will land here.")
            case "favorites":
                EmptyState(systemIcon: "heart", title: "Favorites — coming soon", message: "Saved games will live here.")
            case "profile":
                EmptyState(systemIcon: "person.crop.circle", title: "Profile — coming soon", message: "Sign in / Plus / Logs.")
            default:
                EmptyView()
            }
            if !hideBar {
                VStack {
                    Spacer()
                    FloatingTabBar(tabs: tabs, selectedKey: selected, onSelect: { selected = $0 })
                }
            }
        }
    }
}
```

- [ ] **Step 2: Wrap CatalogView in TabContainer in RootView**

In `ios/UGames/UGamesApp.swift`, find the `case .catalog:` branch in `RootView.body` (around line 55). Wrap the `CatalogView(...)` call in `TabContainer(hideBar: false) { ... }`:

```swift
            case .catalog:
                TabContainer(hideBar: false) {
                    CatalogView(
                        service: catalogService,
                        recentStore: recentStore,
                        favoritesStore: favoritesStore,
                        onGameClick: { game in
                            recentStore.record(game)
                            route = .game(appId: game.appId, title: game.title)
                        },
                        onLoginClick: { route = .auth },
                        onLogsRequest: { route = .logs }
                    )
                }
```

- [ ] **Step 3: Add bottom padding to CatalogView so floating bar doesn't cover content**

Edit `ios/UGames/Views/CatalogView.swift`. Around line 113, find:

```swift
                .padding(12)
```

Replace with:

```swift
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 96)
```

(96pt = 62pt bar + 14pt side padding + 20pt safe-area buffer.)

- [ ] **Step 4: Build and run on simulator**

```bash
cd ios && xcodegen generate
xcodebuild -project UGames.xcodeproj -scheme UGames -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

Then `open UGames.xcodeproj` and Cmd+R on iPhone 15 Simulator.

Manual verification:
- App launches into Home tab with CatalogView visible.
- Floating glass tab bar at the bottom; Home highlighted yellow.
- Tap Browse / Favorites / Profile — each shows "Coming soon" EmptyState.
- Tap a game → push GameView, tab bar hidden.
- Back from game → tab bar reappears, Home selected.

- [ ] **Step 5: Commit**

```bash
git add ios/UGames/Views/TabContainer.swift ios/UGames/UGamesApp.swift ios/UGames/Views/CatalogView.swift
git commit -m "feat(ios): wrap catalog in 4-tab scaffold (Home only, others stub)"
```

---

## Self-review (после написания плана)

**Spec coverage check:**
- ✅ Theme tokens (colors, typography) — Tasks 2-4 (Android), 20 (iOS)
- ✅ `mainColor / iconMainColor / videoUrl` поля — Tasks 5-6 (Android), 21-22 (iOS)
- ✅ media3 — Task 7 (Android only, iOS uses AVKit built-in)
- ✅ Skeleton/EmptyState/ErrorState — Tasks 8-10, 23-25
- ✅ GameCard.Tile/Wide/Square — Tasks 11-13, 26-28
- ✅ HeroSection (stub) — Tasks 14, 29 (видео отложено в Phase 2)
- ✅ StoryCard — Tasks 15, 30
- ✅ GenreChipRow — Tasks 16, 31
- ✅ FloatingTabBar — Tasks 17, 32 (Android API 31+ blur отложен в Phase 5; iOS использует `.ultraThinMaterial`)
- ✅ Bottom-tab scaffold с одним работающим табом — Tasks 18, 33

**Spec items NOT covered in Phase 1 (correctly deferred):**
- HomeViewModel / Home content (Phase 2)
- Browse content (Phase 2)
- Favorites/Profile/About content (Phase 2)
- GameDetail (Phase 3)
- In-game overlay (Phase 4)
- Removal of CatalogScreen / CatalogView / ProfileSheet (Phase 5)
- Auth/Logs cosmetics (Phase 4)
- Real RenderEffect blur on Android (Phase 5)

**Placeholder scan:** No "TBD" / "TODO" / "implement later" / "similar to Task N" patterns found.

**Type consistency:**
- `UGTab` defined in `FloatingTabBar.kt`/`.swift`, used in `TabContainer` — match ✓
- `UGColors.HaloAlpha` (Float) / `UGColor.haloAlpha` (Double) — naming differs by platform-idiom (Kotlin object members PascalCase vs Swift members camelCase), values consistent at 0.35 ✓
- `Game(...)` constructor: Android uses positional + default args; iOS depends on whether existing struct has custom init (Task 21 covers both branches) ✓
- `parseHexColor()` (Android, returns `Color?`) ↔ `Color(hex:)` (iOS, fails-init `Color?`) — both signatures yield optional, callers gate with `?:` / `??` ✓
- `EmptyState(body:)` would collide with `View.body` on iOS — renamed parameter to `message` (Task 24). Android variant keeps `body` (no collision in Kotlin) — matches Compose conventions.

**Found and fixed during self-review:**
- Initial Task 17 first-pass had a bogus `Modifier.androidx.compose.ui.graphics.graphicsLayer` typo and unused `RenderEffect`/`Shader`/`Build` imports. Final task uses semi-transparent fallback only; real blur is consciously deferred to Phase 5.
- iOS Hero / Story preview literals use named-arg `Game(appId:title:rating:...)`. If your existing `Game` struct's init differs, adjust the literal names in previews — no runtime impact.
- `EmptyState` parameter rename `body` → `message` propagated to iOS `TabContainer` (Task 33).

---

## Next plans (will be created when Phase 1 lands)

- `2026-05-XX-ui-ux-redesign-phase-2-screens.md` — HomeScreen, BrowseScreen, FavoritesScreen, ProfileScreen, AboutScreen + ViewModels.
- `2026-05-XX-ui-ux-redesign-phase-3-game-detail.md` — GameDetailScreen, переключение клика → push Detail.
- `2026-05-XX-ui-ux-redesign-phase-4-in-game.md` — In-game overlay, load progress, Auth/rotation polish, long-press quick-actions.
- `2026-05-XX-ui-ux-redesign-phase-5-cleanup.md` — Удаление старого кода, accessibility, Android RenderEffect blur, smoke-tests.
