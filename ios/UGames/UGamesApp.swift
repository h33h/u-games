import SwiftUI
import UIKit
import WebKit

@main
struct UGamesApp: App {
    init() {
        _ = SharedCookieStore.shared

        URLCache.shared = URLCache(
            memoryCapacity: 30 * 1024 * 1024,
            diskCapacity: 250 * 1024 * 1024,
            diskPath: "ugames-image-cache"
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

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
            UGColor.bg0.ignoresSafeArea()
            TabContainer(
                catalogService: catalogService,
                favoritesStore: favoritesStore,
                onLogsRequest: { push(.logs) },
                onGameOpen: { game in push(.gameDetail(game)) },
                onLoginClick: { push(.auth) },
                onSignOut: {
                    Task { await catalogService.clearSession() }
                },
                onShareGame: { game in
                    sharePayload = SharePayload(title: game.title, url: game.playUrl)
                },
            )
            if let route = routeStack.last {
                routeOverlay(for: route)
                    .background(UGColor.bg0.ignoresSafeArea())
                    .id(routeId(route))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: routeStack.count)
        .sheet(item: $sharePayload) { payload in
            ShareSheet(payload: payload)
        }
        .onOpenURL { url in
            if let appId = parseDeepLink(url) {
                reset(to: .game(appId: appId, title: ""))
            }
        }
    }

    @ViewBuilder
    private func routeOverlay(for route: Route) -> some View {
        switch route {
        case .catalog:
            EmptyView()
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
        case .game(let appId, let title):
            GameView(
                appId: appId,
                title: title,
                scripts: injectedScripts,
                blockList: blockList,
                onBack: {
                    pop()

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

    private func routeId(_ route: Route) -> String {
        switch route {
        case .catalog: return "catalog"
        case .gameDetail(let g): return "detail-\(g.appId)"
        case .game(let id, _): return "game-\(id)"
        case .auth: return "auth"
        case .logs: return "logs"
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

struct SharePayload: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let url: URL?
}

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

struct ShareSheet: UIViewControllerRepresentable {
    let payload: SharePayload

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = [payload.title]
        if let url = payload.url { items.append(url) }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
