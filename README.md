# U-Games — Yandex.Games без рекламы

Нативные обёртки (Android + iOS) над `yandex.ru/games`, которые запускают игры без рекламы и в полноэкранном PWA-стиле. Свой каталог игр загружается напрямую из JSON-эндпоинтов Yandex; авторизация Яндекс ID и сохранение прогресса работают штатно.

## Защита от рекламы — три слоя

1. **Honest-path JSON-патч** (`shared/inject/honest-path.js`). Хук `JSON.parse` перезаписывает поля `__appData__` / `__playPageData__` до того, как React-фронт Яндекса их прочитает: `advPartnerInfo.advEnabledByPartner=false`, `playerInfo.hasYaPlus=true`, `isAdvStickyBannerEnabled=false`, `request.isPWA=true`, `allAdvBlocks={}` и т.д. В результате сам Яндекс-фронт не запрашивает GPT/Prebid/Metrica.
2. **SDK-стаб** (`shared/inject/ya-sdk-stub.js`). На случай, если игра вызывает `ysdk.adv.showFullscreenAdv()` напрямую, стаб мгновенно отрабатывает `onClose(false)`. Остальные методы SDK (storage, getPlayer, environment, deviceInfo, features.*) проксируются к настоящему SDK.
3. **URL block-list** (`shared/blocklist/ad-domains.txt`). На уровне WebView режутся запросы на рекламные домены (Yandex Metrica, Google GPT, Prebid SSPs, Funding Choices и др.) — страховка от того, что первые два слоя что-то пропустят.

## Структура

```
u-games/
├── shared/
│   ├── inject/        # honest-path.js, ya-sdk-stub.js, pwa-mode.css, pwa-mode.js
│   ├── blocklist/     # ad-domains.txt
│   └── catalog/       # feed-schema.md (документация эндпоинта Яндекса)
├── android/           # Kotlin + Jetpack Compose
└── ios/               # Swift + SwiftUI (Package.swift проект)
```

Все артефакты в `shared/` копируются в bundle обеих платформ (Android — через `sourceSets.main.assets.srcDirs`, iOS — `Package.swift resources`).

## CI / Релизы

Два GitHub Actions workflow:

- `.github/workflows/android.yml` — на push/PR в `main`, затрагивающие `android/**` или `shared/**`, собирает debug APK и публикует как artifact.
- `.github/workflows/release.yml` — на push тега `v*` (или ручной запуск через UI):
  - **ubuntu-latest** собирает **release APK**, подписанный auto-generated debug keystore → пригоден для sideload, **не для Google Play**.
  - **macos-14** через [XcodeGen](https://github.com/yonaskolb/XcodeGen) генерирует Xcode-проект из `ios/project.yml`, собирает Release-конфиг с `CODE_SIGNING_ALLOWED=NO` и упаковывает результат в **unsigned `.ipa`** (Payload/UGames.app внутри zip).
  - Создаёт GitHub Release `vX.Y.Z` и прикрепляет оба файла (`u-games-vX.Y.Z.apk` и `u-games-vX.Y.Z-unsigned.ipa`).

Чтобы выпустить релиз:
```bash
git tag v0.1.0
git push origin v0.1.0
```
В разделе **Releases** на GitHub появится релиз с APK и IPA.

**Установка unsigned IPA**: реподпись через [AltStore](https://altstore.io/) / [SideStore](https://sidestore.io/) бесплатным Apple ID (7-day signing) или Apple Developer ($99/год, 1 год). Через TestFlight/App Store unsigned IPA не пройдёт.

## Сборка Android

### Требования
- JDK 17 (`openjdk-17-jdk-headless`)
- Android SDK с `platforms;android-34` и `build-tools;34.0.0`
- ~3 GB RAM свободной + swap (build гоняет два JVM-демона)

### Сборка

```bash
export ANDROID_HOME=/opt/android-sdk
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
cd android
./gradlew :app:assembleDebug
```

Готовый APK: `android/app/build/outputs/apk/debug/app-debug.apk`.

### Установка (sideload)
```bash
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
```
Или скопировать APK на телефон и открыть из файлового менеджера (предварительно включить «Установка из неизвестных источников» для конкретного приложения).

### Проверка (через chrome://inspect)
1. Подключить телефон по USB, включить USB Debugging.
2. На десктопе открыть Chrome → `chrome://inspect/#devices`.
3. В списке найти `WebView in games.yandex.wrap` → Inspect.
4. Tab Network: при запуске игры не должно быть запросов на:
   - `securepubads.g.doubleclick.net/gampad/ads?...`
   - `mc.yandex.ru/watch/*`
   - `pagead2.googlesyndication.com/*`
   - `fundingchoicesmessages.google.com/*`
5. Tab Console: `JSON.parse(document.getElementById('__appData__').textContent).advPartnerInfo.advEnabledByPartner` → `false` (если honest-path сработал).
6. В iframe-фрейме (переключиться через select сверху Console): `window.YaGames` определён, `window.__yga_stub__ === true`.

## Сборка iOS

### Требования
- macOS + Xcode 15+
- iOS 15+ target
- Apple Developer аккаунт ($99/год) для подписи или AltStore/SideStore для бесплатного 7-day signing

### Открытие проекта
```bash
cd ios
open Package.swift   # откроется в Xcode
```
или создать Xcode-проект-обёртку, добавив SPM пакет `UGames`.

### Установка (sideload)
- **TestFlight**: archive → upload → пригласить тестеров. Внутреннее тестирование (до 100 чел.) — без external review.
- **AltStore / SideStore**: подписать бесплатным Apple ID, переподписывать каждые 7 дней.
- **Self-signing на jailbroken** устройство.

App Store не примет — это обёртка над сторонним сервисом с блокировкой рекламы (нарушает гайдлайны 4.2, 5.2).

## Распространение и риски

- В Google Play и App Store такая обёртка реджектится: правила про minimum functionality и блокировку чужой рекламы.
- ToS Яндекс.Игр запрещает блокировать рекламу игр (это лишает разработчиков и Яндекс монетизации). Используйте на свой страх и риск, для личных целей.
- Hashed CSS-классы Yandex (`header-wrapper-critical-module__header--*`) могут поменяться при ребилдах фронта — потребуется обновить селекторы в `pwa-mode.css`.
- Catalog API эндпоинт публичный, но не закреплён в контракте; Yandex может добавить anti-bot или поменять формат — нужен fallback.

## Что внутри

### Android (`android/`)
- `app/build.gradle.kts` — AGP 8.5, Kotlin 2.0, Compose, Ktor, Room, Coil, AndroidX WebKit
- `kotlin/games/yandex/wrap/MainActivity.kt` — single Activity + Compose root
- `kotlin/games/yandex/wrap/ui/CatalogScreen.kt` — `LazyVerticalGrid` со списком игр
- `kotlin/games/yandex/wrap/ui/GameScreen.kt` — полноэкранный WebView
- `kotlin/games/yandex/wrap/webview/GameWebView.kt` — WebView setup, инжекция через `WebViewCompat.addDocumentStartJavaScript` с `allowedOriginRules`
- `kotlin/games/yandex/wrap/webview/AdBlockingClient.kt` — `WebViewClient.shouldInterceptRequest` блокирует URL по списку
- `kotlin/games/yandex/wrap/webview/PopupHandler.kt` — `WebChromeClient.onCreateWindow` для passport.yandex.ru OAuth popup
- `kotlin/games/yandex/wrap/catalog/CatalogApi.kt` — Ktor клиент для `yandex.ru/games/api/catalogue/v2/*`
- `kotlin/games/yandex/wrap/data/AppDatabase.kt` — Room: cache + favorites

### iOS (`ios/`)
- `Package.swift` — SPM пакет с ресурсами
- `UGames/UGamesApp.swift` — `@main`, root navigation
- `UGames/Views/CatalogView.swift` — `LazyVGrid` со списком
- `UGames/Views/GameView.swift` — полноэкранный `WKWebView`
- `UGames/WebView/GameWebView.swift` — `UIViewRepresentable` обёртка, `WKUserScript(forMainFrameOnly: false)` для iframe-инжекции, `WKContentRuleList` для URL-блокировки
- `UGames/Catalog/CatalogService.swift` — `URLSession` клиент для catalog API
