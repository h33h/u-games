# Проверка провайдера Яндекс Игр

Дата: 2026-10-10. Chrome DevTools, отдельная гостевая сессия ugames-probe.

## Наблюдения

- «Мир домовят» (435086): внешний play-yandex.mirdomovyat.ru не ответил;
  каталог и оболочка загрузились. Игровой сценарий NOT RUN.
- Red Ball 4 (263344): игра с app-263344.cdn.games.yandex.net загрузилась.
  Ранний скрипт перехватил YaGames.init(), сохранил SDK и заменил adv-методы.
  Перехвачен один showFullscreenAdv; callbacks.onClose(false) завершил запрос.
  После выбора первого уровня игра продолжала работать, персонаж двигался.
- «3D Куб 2048» (181447): первый фрейм app-181447.games.s3.yandex.net создал
  SDK; вложенный фрейм 3d2048ru.website.yandexcloud.net отрисовал игру.
  Перехвачен showFullscreenAdv, переход из меню в первый уровень работает.
- «Злые рыбки» (97693): SDK перехвачен, меню и выбор уровней работают.

SDK игры загружался по /sdk/_/v2.5871b227ff69bc337568.js.
adv содержит showFullscreenAdv, showRewardedVideo, showBannerAdv,
hideBannerAdv, getBannerAdvStatus. Инстанс доступен через результат init();
методы допускают замену. Реальный fullscreen-вызов использует {callbacks}.

## Реклама самой оболочки сервиса

Она показывается независимо от adv-методов игры. Наблюдались отдельная
полноэкранная рекламная модалка и sticky-контейнер. Закрытие кнопкой
.close-button_type_adv-fullscreen убрало модалку и позволило играть.

Подтверждённые рекламные ресурсы:
- https://yandex.ru/ads/system/context.js
- https://yandex.ru/ads/meta/3561051
- https://an.yandex.ru/ (рекламные mapuid-запросы)
- https://yastatic.net/s3/games-static/static-data/ads-async.js
- https://yastatic.net/safeframe-bundles/0.89/1-1-0/render.html

Подтверждённые контейнеры:
- .sticky-banner-container
- .aab-adv
- .play-modal.adv-focusable (полноэкранная и rewarded-модалка)
- .close-button_type_adv-fullscreen (закрытие отдельной рекламной модалки)

Все ресурсы Яндекса, SDK, game-CDN и авторизация остаются разрешёнными.

## Статус доказательств

| Сценарий | Результат |
| --- | --- |
| Доступ к реальному SDK и замена рекламного метода | CONFIRMED |
| Продолжение Red Ball 4 после завершения SDK fullscreen без показа | CONFIRMED |
| Перехват в первом из двух игровых фреймов | CONFIRMED |
| Полное отсутствие рекламы в итоговых мобильных оболочках | NOT RUN |
| Фактический бонус реальной игры по rewarded-кнопке | NOT RUN |
| Вход и сохранение личного прогресса | NOT RUN |

Rewarded-поведение реализуется по контракту SDK и проверяется сначала
поведенческими тестами, затем реальной кнопкой игры в этапе мобильной
приёмки. Отсутствие такой проверки не означает доказанную совместимость
наград всего каталога.

Источники: [SDK](https://yandex.ru/dev/games/doc/ru/sdk/sdk-adv),
[Red Ball 4](https://yandex.ru/games/app/red-ball-4-263344),
[3D Куб 2048](https://yandex.ru/games/app/3d-kub-2048-181447),
[Злые рыбки](https://yandex.ru/games/app/zlye-rybki-97693).
