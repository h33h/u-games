# U Games

Личный клиент Яндекс Игр для Android и iPhone. Каталог и игры открываются
внутри приложения. Общий адаптер завершает рекламные вызовы SDK без показа
и выдаёт награды за видео; фильтры убирают рекламные ресурсы и блоки портала.
Вход и сохранения остаются на стороне Яндекса.

## Сборка

Нужны Node.js 20+, JDK 17, Android SDK 36 и Xcode с XcodeGen для iOS.

```sh
npm test
npm run build:shared
```

Android: укажи путь к SDK в локальном android/local.properties
(`sdk.dir=/absolute/path/to/android-sdk`), затем:

```sh
cd android
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
```

APK: android/app/build/outputs/apk/debug/app-debug.apk.
Для нативных тестов подключи устройство или эмулятор и выполни
`./gradlew :app:connectedDebugAndroidTest`.

iOS:

```sh
xcodegen generate --spec ios/project.yml
xcodebuild build -project ios/UGames.xcodeproj -scheme UGames \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Открой сгенерированный ios/UGames.xcodeproj, выбери свою Signing Team и
подключённый iPhone, затем Run. Подписывающая команда не хранится в репозитории.
Сборка для симулятора не устанавливается на физический iPhone.

## Проверено

- Общий JavaScript, упаковка ресурсов и фильтры: Node.js tests.
- Android: нативные тесты на Android 16 / WebView 133, включая внешний
  iframe, новое окно, сбой рендерера и несовместимый SDK.
- iPhone Simulator: ранняя инъекция во все фреймы, фильтрация первого
  рекламного запроса, новые окна и обработка ошибки SDK.
- Реальные игры на iPhone Simulator: «Слова из слова» (10 → 12 подсказок
  без видео), Red Ball 4 (первый уровень и управление), Hexa Block 2048
  (запуск и игровой ход без полноэкранной рекламы и нижнего баннера).
- Штатная форма Яндекс ID открывается в приложении.

Весь каталог доступен без списка разрешённых игр. Совместимость каждой
игры не доказана. Изменения SDK и способов показа рекламы Яндекса требуют
обновления адаптера. Если рекламный API нельзя безопасно перехватить,
приложение показывает ошибку вместо включения рекламы.

Живая проверка Android встретила капчу Яндекса; проверка после неё пока не
выполнена. Вход с личными данными и синхронизация прогресса между двумя
физическими телефонами требуют проверки владельцем аккаунта.

Подробности: [спецификация](docs/superpowers/specs/2026-10-10-u-games-design.md),
[план](docs/superpowers/plans/2026-10-10-u-games.md),
[наблюдения SDK](docs/verification/2026-10-10-provider-investigation.md).
