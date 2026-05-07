import SwiftUI
import WebKit

@main
struct UGamesApp: App {
    init() {
        // Bridge WKWebView's cookies into URLSession.shared so catalog HTTP
        // requests see the same session as the in-app WebView (auth screen).
        _ = SharedCookieStore.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

/// Parse `ugames://app/<id>` deep links. Also tolerates
/// `https://yandex.com/games/app/<id>` in case Universal Links are added
/// later. Returns the appId or nil.
func parseDeepLink(_ url: URL) -> Int64? {
    let scheme = url.scheme?.lowercased() ?? ""
    let segments = url.pathComponents.filter { $0 != "/" }
    switch scheme {
    case "ugames":
        if url.host == "app" {
            return segments.first.flatMap { Int64($0) }
        }
        return nil
    case "https", "http":
        if let host = url.host,
           host.hasSuffix("yandex.com") || host.hasSuffix("yandex.ru"),
           let idx = segments.firstIndex(of: "app"), idx + 1 < segments.count {
            return Int64(segments[idx + 1])
        }
        return nil
    default:
        return nil
    }
}

struct RootView: View {
    @State private var route: Route = .catalog
    @StateObject private var catalogService = CatalogService()
    @StateObject private var recentStore = RecentGamesStore.shared
    @StateObject private var favoritesStore = FavoritesStore.shared
    private let injectedScripts = InjectedScripts.load()
    private let blockList = BlockList.load()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch route {
            case .catalog:
                TabContainer(
                    catalogService: catalogService,
                    recentStore: recentStore,
                    favoritesStore: favoritesStore,
                    onLogsRequest: { route = .logs },
                    onGameOpen: { game in
                        recentStore.record(game)
                        route = .game(appId: game.appId, title: game.title)
                    },
                    onLoginClick: { route = .auth },
                    onSignOut: {
                        Task { await catalogService.clearSession() }
                    },
                )
            case .game(let appId, let title):
                GameView(
                    appId: appId,
                    title: title,
                    scripts: injectedScripts,
                    blockList: blockList,
                    onBack: {
                        route = .catalog
                        // Yandex's server-side recentGames updates on the
                        // play session — let HomeViewModel know so it
                        // re-fetches the feed and the just-played game
                        // appears in the Recently played row.
                        catalogService.notifyGameSessionEnded()
                    },
                )
            case .auth:
                AuthView(onClose: {
                    route = .catalog
                    Task { await catalogService.refreshProfile() }
                })
            case .logs:
                LogsView(onClose: { route = .catalog })
            }
        }
        .onOpenURL { url in
            if let appId = parseDeepLink(url) {
                route = .game(appId: appId, title: "")
            }
        }
    }
}

enum Route: Equatable {
    case catalog
    case game(appId: Int64, title: String)
    case auth
    case logs
}
