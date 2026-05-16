# Yandex Games Catalog API

Public-ish JSON endpoint discovered via live network inspection. Used without
authentication; mobile-friendly layout when User-Agent is mobile.

## Endpoint

```
GET https://yandex.ru/games/api/catalogue/v2/feed/
```

## Query parameters

| Name                | Example                  | Notes                                  |
|---------------------|--------------------------|----------------------------------------|
| `lang`              | `en`, `ru`               | Localized titles/descriptions          |
| `platform`          | `android_other`          | Triggers mobile layout                 |
| `with_promos`       | `true`                   | Include sponsored cards                |
| `games_count`       | `12`, `24`               | Per page                               |
| `categorized_size`  | `5`                      | Count of categorized rows              |
| `suggested_width`   | `3`                      | Grid width for suggested block         |
| `suggested_rows`    | `4`                      | Rows in suggested block                |
| `with_recent_games` | `true`                   | Include "recently played" row          |
| `client_width`      | `412`                    | Used for cover-image sizing            |
| `client_height`     | `915`                    | Same                                   |
| `page_id`           | `Z2FtZXNTa2lwPTEy`       | Base64 of `gamesSkip=N` for pagination |

## Response shape

```json
{
  "feed": [
    {
      "type": "suggested" | "categorized" | "promo" | ...,
      "size": "s" | "l",
      "title": "...",
      "items": [
        {
          "appID": 417011,
          "title": "Block Puzzle: Falling shapes",
          "rating": 4.9,
          "ratingCount": 39,
          "categoryIDs": [12, 5],
          "categoriesNames": ["puzzles", "casual"],
          "developer": {
            "id": 104509,
            "name": "safarov-en",
            "transliteratedName": "safarov-en"
          },
          "media": {
            "cover": {
              "prefix-url": "https://avatars.mds.yandex.net/get-games/.../",
              "mainColor": "#41B4F6"
            },
            "icon": {
              "prefix-url": "https://avatars.mds.yandex.net/get-games/.../",
              "mainColor": "#8BDEFF"
            },
            "videos": [
              {
                "embedUrl": "https://frontend.vh.yandex.ru/player/...",
                "previewUrl": "https://video-preview.s3.yandex.net/.../preview.mp4",
                "mp4StreamUrl": "https://games.s3.yandex.net/videos/.../file.mp4",
                "thumbnailUrl": "https://avatars.mds.yandex.net/get-vh/.../orig",
                "width": 1920, "height": 1080
              }
            ]
          }
        }
      ]
    }
  ],
  "pageInfo": { ... },
  "promos": [ ... ],
  "gamesWithPromos": [ ... ],
  "lastPlayedTS": null,
  "shareImage": "https://...",
  "siteNavigationLinks": { "categories": [...], "tags": [...] },
  "gamesRequestId": "..."
}
```

## Image URLs

Build the cover URL by appending a size suffix to `prefix-url`. Common suffixes:

- `pjpg256x256` — square icon
- `pjpg250x140` — wide cover
- `orig` — original

Example:
```
https://avatars.mds.yandex.net/get-games/15351989/2a00000199f7d0b8950a31ebace1a3e3be78/pjpg256x256
```

## Game launch URL

```
https://yandex.ru/games/app/{appID}
```

The wrapper page creates an iframe pointing at `app-{appID}.games.s3.yandex.net`
where the actual game lives. Loading the iframe URL directly bypasses the SDK
postMessage handshake and breaks `init()`, so we always load the wrapper URL.

## Related endpoint

```
GET https://yandex.ru/games/api/catalogue/v2/similar_games/?app_id={appID}&games_count=16&lang=ru&platform=android_other
```

Same item shape, used to populate the "Similar games" row.
