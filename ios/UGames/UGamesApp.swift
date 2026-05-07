import SwiftUI
import UIKit
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
    /// Phase 3: routes form a *stack* so Detail → Game → Back lands back
    /// on Detail rather than the catalog. The bottom of the stack is
    /// implicit (`.catalog`); only pushed routes live here.
    @State private var routeStack: [Route] = []
    @State private var sharePayload: SharePayload?
    @StateObject private var catalogService = CatalogService()
    @StateObject private var favoritesStore = FavoritesStore.shared
    private let injectedScripts = InjectedScripts.load()
    private let blockList = BlockList.load()

    private var currentRoute: Route { routeStack.last ?? .catalog }

    private func push(_ route: Route) { routeStack.append(route) }
    private func pop() { _ = routeStack.popLast() }
    private func reset(to route: Route) { routeStack = [route] }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch currentRoute {
            case .catalog:
                TabContainer(
                    catalogService: catalogService,
                    favoritesStore: favoritesStore,
                    onLogsRequest: { push(.logs) },
                    onGameOpen: { game in
                        // Phase 3: cards push Detail first; Detail's Play
                        // button is what pushes the WebView.
                        push(.gameDetail(game))
                    },
                    onLoginClick: { push(.auth) },
                    onSignOut: {
                        Task { await catalogService.clearSession() }
                    },
                )
            case .gameDetail(let game):
                GameDetailHost(
                    game: game,
                    catalogService: catalogService,
                    favoritesStore: favoritesStore,
                    onBack: { pop() },
                    onPlay: { g in push(.game(appId: g.appId, title: g.title)) },
                    onShare: { g in
                        sharePayload = SharePayload(title: g.title, url: g.playUrl)
                    },
                    onSimilarClick: { g in push(.gameDetail(g)) }
                )
                // Distinct id-per-game so SwiftUI tears down + rebuilds
                // (with a fresh @StateObject GameDetailViewModel) when
                // navigating Detail(A) → similar tile → Detail(B).
                .id(game.appId)
            case .game(let appId, let title):
                GameView(
                    appId: appId,
                    title: title,
                    scripts: injectedScripts,
                    blockList: blockList,
                    onBack: {
                        pop()
                        // Yandex's server-side recentGames updates on the
                        // play session — let HomeViewModel know so it
                        // re-fetches the feed and the just-played game
                        // appears in the Recently played row.
                        catalogService.notifyGameSessionEnded()
                    },
                )
            case .auth:
                AuthView(onClose: {
                    pop()
                    Task { await catalogService.refreshProfile() }
                })
            case .logs:
                LogsView(onClose: { pop() })
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(payload: payload)
        }
        .onOpenURL { url in
            if let appId = parseDeepLink(url) {
                // Cold-start deep link bypasses Detail (we have only the
                // appId, not a full Game) and lands straight in the
                // WebView. Mirror Android's MainActivity.parseDeepLink.
                reset(to: .game(appId: appId, title: ""))
            }
        }
    }
}

enum Route: Equatable {
    case catalog
    case gameDetail(Game)
    case game(appId: Int64, title: String)
    case auth
    case logs
}

/// Identifiable wrapper so SwiftUI's `.sheet(item:)` can present the
/// system share sheet driven by an Optional. New `id` per invocation
/// makes the sheet re-present even if the same game is shared twice in
/// a row.
struct SharePayload: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let url: URL?
}

/// Owns a `GameDetailViewModel` via `@StateObject` so the VM survives
/// SwiftUI body re-renders. RootView feeds it via `.id(game.appId)` so
/// navigating Detail(A) → Similar(B) → Detail(B) tears the host down
/// and creates a fresh VM with fresh similar-fetch.
private struct GameDetailHost: View {
    let game: Game
    @ObservedObject var catalogService: CatalogService
    @ObservedObject var favoritesStore: FavoritesStore
    let onBack: () -> Void
    let onPlay: (Game) -> Void
    let onShare: (Game) -> Void
    let onSimilarClick: (Game) -> Void

    @StateObject private var viewModel: GameDetailViewModel

    init(
        game: Game,
        catalogService: CatalogService,
        favoritesStore: FavoritesStore,
        onBack: @escaping () -> Void,
        onPlay: @escaping (Game) -> Void,
        onShare: @escaping (Game) -> Void,
        onSimilarClick: @escaping (Game) -> Void
    ) {
        self.game = game
        self.catalogService = catalogService
        self.favoritesStore = favoritesStore
        self.onBack = onBack
        self.onPlay = onPlay
        self.onShare = onShare
        self.onSimilarClick = onSimilarClick
        _viewModel = StateObject(
            wrappedValue: GameDetailViewModel(game: game, service: catalogService)
        )
    }

    var body: some View {
        GameDetailView(
            viewModel: viewModel,
            favorites: favoritesStore,
            onBack: onBack,
            onPlay: onPlay,
            onShare: onShare,
            onSimilarClick: onSimilarClick,
        )
    }
}

/// Bridges UIActivityViewController for SwiftUI. Single-purpose: share a
/// game's playUrl + title from GameDetailView's top icon.
struct ShareSheet: UIViewControllerRepresentable {
    let payload: SharePayload

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = [payload.title]
        if let url = payload.url { items.append(url) }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
