import SwiftUI

@main
struct UGamesApp: App {
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
    private let injectedScripts = InjectedScripts.load()
    private let blockList = BlockList.load()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch route {
            case .catalog:
                CatalogView(service: catalogService) { game in
                    route = .game(appId: game.appId, title: game.title)
                }
            case .game(let appId, let title):
                GameView(
                    appId: appId,
                    title: title,
                    scripts: injectedScripts,
                    blockList: blockList,
                    onBack: { route = .catalog }
                )
            }
        }
    }
}

enum Route: Equatable {
    case catalog
    case game(appId: Int64, title: String)
}
