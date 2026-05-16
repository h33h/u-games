import SwiftUI
import UIKit
import WebKit

@main
struct UGamesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.gameActive ? .allButUpsideDown : .portrait
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
           host == Constants.Network.host,
           let idx = segments.firstIndex(of: "app"), idx + 1 < segments.count {
            return Int64(segments[idx + 1])
        }
        return nil
    default:
        return nil
    }
}

struct RootView: View {
    private let environment: AppEnvironment
    @State private var gameSession: GameSession?
    @State private var authPresented: Bool = false
    @State private var logsPresented: Bool = false
    @State private var sharePayload: SharePayload?
    @StateObject private var catalogService: CatalogService
    @StateObject private var favoritesStore = FavoritesStore.shared
    private let injectedScripts = InjectedScripts.load()
    private let blockList = BlockList.load()

    init(environment: AppEnvironment = .live) {
        self.environment = environment
        _catalogService = StateObject(wrappedValue: CatalogService(environment: environment))
    }

    var body: some View {
        ZStack {
            UGColor.Surface.base.ignoresSafeArea()
            TabContainer(
                catalogService: catalogService,
                favoritesStore: favoritesStore,
                onPlayGame: { game in
                    gameSession = GameSession(appId: game.appId, title: game.title)
                },
                onLoginClick: { authPresented = true },
                onLogsRequest: { logsPresented = true },
                onSignOut: {
                    Task { await catalogService.clearSession() }
                },
                onShareGame: { game in
                    sharePayload = SharePayload(title: game.title, url: game.playUrl)
                }
            )
        }
        .fullScreenCover(item: $gameSession) { session in
            GameView(
                appId: session.appId,
                title: session.title,
                scripts: injectedScripts,
                blockList: blockList,
                onBack: {
                    gameSession = nil
                    catalogService.notifyGameSessionEnded()
                }
            )
        }
        .fullScreenCover(isPresented: $authPresented) {
            AuthView(onClose: {
                authPresented = false
                Task { await catalogService.refreshProfile() }
            })
        }
        .sheet(isPresented: $logsPresented) {
            LogsView(onClose: { logsPresented = false })
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(payload: payload)
        }
        .onOpenURL { url in
            if let appId = parseDeepLink(url) {
                gameSession = GameSession(appId: appId, title: "")
            }
        }
    }
}

struct GameSession: Identifiable, Equatable {
    let id = UUID()
    let appId: Int64
    let title: String
}

struct SharePayload: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let url: URL?
}

struct GameDetailHost: View {
    let game: Game
    @ObservedObject var catalogService: CatalogService
    @ObservedObject var favoritesStore: FavoritesStore
    let onPlay: (Game) -> Void
    let onShare: (Game) -> Void
    let onSimilarClick: (Game) -> Void

    @StateObject private var viewModel: GameDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        game: Game,
        catalogService: CatalogService,
        favoritesStore: FavoritesStore,
        onPlay: @escaping (Game) -> Void,
        onShare: @escaping (Game) -> Void,
        onSimilarClick: @escaping (Game) -> Void
    ) {
        self.game = game
        self.catalogService = catalogService
        self.favoritesStore = favoritesStore
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
            onBack: { dismiss() },
            onPlay: onPlay,
            onShare: onShare,
            onSimilarClick: onSimilarClick
        )
        .toolbar(.hidden, for: .navigationBar)
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
