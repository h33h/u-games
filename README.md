# UGames

Мобильное приложение для браузерных игр из каталога Яндекс Игр. Открывайте каталог и запускайте игры внутри приложения на Android и iPhone.

## Возможности

- Каталог и игры в WebView с оформлением UGames.
- Блокировка рекламных ресурсов и скрытие рекламных элементов каталога.
- Адаптер игрового SDK для обработки рекламных вызовов и выдачи наград в совместимых играх.
- Локальные бесплатные покупки в играх, которые поддерживают клиентские квитанции. Игры с серверной проверкой платежей могут быть несовместимы.
- Навигация внутри приложения, повторная загрузка при ошибках и поддержка портретной и альбомной ориентации.

Для загрузки каталога и игр нужно подключение к интернету. Совместимость зависит от конкретной игры и её SDK.

## Подготовка

Установите Node.js 20.19+, 22.13+ или 24+ и npm.

```sh
git clone https://github.com/h33h/u-games.git
cd u-games
npm ci
npm run build:shared
```

Команда `build:shared` собирает JavaScript, оформление и правила блокировки для обеих платформ. Нативные сборки также вызывают её автоматически.

## Android

Требования: Android Studio, Android SDK 36 и JDK 17 или новее, совместимый с Gradle 9.6. Минимальная версия устройства: Android 7.0 (API 24).

1. Откройте папку `android/` в Android Studio.
2. Укажите путь к Android SDK в настройках IDE или в `android/local.properties` через `sdk.dir`.
3. Выберите устройство или эмулятор и запустите приложение.

Чтобы собрать отладочный APK из терминала:

```sh
cd android
./gradlew assembleDebug
```

APK: `android/app/build/outputs/apk/debug/app-debug.apk`.

## iOS

Требования: macOS, Xcode и XcodeGen. Минимальная версия устройства: iOS 15.

```sh
brew install xcodegen
cd ios
xcodegen generate
open UGames.xcodeproj
```

В Xcode выберите схему `UGames` и симулятор iPhone, затем запустите приложение. Для запуска на устройстве укажите свою команду разработки в Signing & Capabilities. Node.js должен быть доступен скрипту сборки Xcode.

## Проверки

Из корня репозитория:

```sh
npm test              # тесты общего JavaScript, правил, оформления и покупок
npm run format:check  # проверка форматирования
npm run check         # линтеры и JavaScript-тесты
```

Для проверок Kotlin, Swift и shell-скриптов установите инструменты из `Brewfile` командой `brew bundle` на macOS.

Тесты Android:

```sh
cd android
./gradlew testDebugUnitTest
./gradlew connectedDebugAndroidTest  # нужен эмулятор или устройство
```

Тесты iOS запускайте через Product → Test в Xcode со схемой `UGames`.

## Авторелиз и защита main

GitHub Actions проверяет каждый PR в `main` и каждый коммит в `main`: форматирование,
линтеры, общие JavaScript-тесты, Android unit-тесты и Android Lint, iOS-тесты на
симуляторе, Release-сборки Android и iOS. После успешного завершения всех трёх jobs
(`Quality`, `Android`, `iOS`) коммит в `main` публикует GitHub Release с файлами:

- `UGames.apk` — APK, подписанный постоянным ключом Android.
- `UGames-unsigned.ipa` — сборка для физических iPhone без подписи. Перед установкой
  её нужно переподписать своим сертификатом и provisioning profile.
- `SHA256SUMS.txt` — контрольные суммы обоих файлов.

Версия приложения берётся из `package.json`, номер сборки — из `github.run_number`.
Тег имеет вид `v0.1.0-build.42-abcdef0`. Каждый запуск для `main` сохраняется;
новый коммит не отменяет предыдущую сборку. Повторный запуск того же workflow
использует тот же тег. Релиз сначала создаётся как черновик и публикуется после
загрузки обоих файлов. Ручной запуск через Actions → CI and Release также доступен;
публикация разрешена только из `main`.

Для подписи Android в Settings → Secrets and variables → Actions нужны секреты
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` и
`ANDROID_KEY_PASSWORD`. Keystore передаётся в Base64. Сохраните резервную копию
ключа и паролей вне GitHub: замена ключа нарушит обновление установленных APK.
В PR ключ не используется и APK собирается без подписи.

Настройки защиты находятся в `.github/main-protection.json`. Администратор может
применить их после включения workflow:

```sh
gh api --method PUT repos/h33h/u-games/branches/main/protection \
  --input .github/main-protection.json
```

Защита требует PR, успешных проверок `Quality`, `Android`, `iOS`, актуальной базы
`main` и разрешения обсуждений. Force-push и удаление запрещены; правила действуют
и для администраторов. В одиночном проекте чужой approving review не обязателен.
Для приватного репозитория GitHub требует тариф с поддержкой protected branches.

## Структура проекта

| Папка      | Содержимое                                                              |
| ---------- | ----------------------------------------------------------------------- |
| `android/` | Android-приложение на Kotlin, WebView и нативные тесты                  |
| `ios/`     | iOS-приложение на Swift, WKWebView и нативные тесты                     |
| `shared/`  | Адаптер SDK, правила блокировки, оформление, ресурсы и JavaScript-тесты |
| `scripts/` | Сборка общих ресурсов, форматирование и линтеры                         |

Меняйте правила блокировки в `shared/ad-rules.json`, поведение SDK в `shared/ad-adapter.js`, оформление в `shared/portal-theme.css` и `shared/portal-theme.js`. После изменений пересоберите общие ресурсы.

## Лицензия

Код проекта распространяется по [MIT](LICENSE).
