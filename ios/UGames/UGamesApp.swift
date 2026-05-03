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

struct RootView: View {
    @State private var route: Route = .catalog
    @StateObject private var catalogService = CatalogService()
    @StateObject private var recentStore = RecentGamesStore.shared
    private let injectedScripts = InjectedScripts.load()
    private let blockList = BlockList.load()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch route {
            case .catalog:
                CatalogView(
                    service: catalogService,
                    recentStore: recentStore,
                    onGameClick: { game in
                        recentStore.record(game)
                        route = .game(appId: game.appId, title: game.title)
                    },
                    onLoginClick: { route = .auth }
                )
            case .game(let appId, let title):
                GameView(
                    appId: appId,
                    title: title,
                    scripts: injectedScripts,
                    blockList: blockList,
                    onBack: { route = .catalog }
                )
            case .auth:
                AuthView(onClose: {
                    route = .catalog
                    Task { await catalogService.refreshProfile() }
                })
            }
        }
    }
}

enum Route: Equatable {
    case catalog
    case game(appId: Int64, title: String)
    case auth
}
