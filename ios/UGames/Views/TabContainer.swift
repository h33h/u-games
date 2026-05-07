import SwiftUI

enum ProfileRoute: Hashable {
    case about
}

struct TabContainer: View {
    @ObservedObject var catalogService: CatalogService
    @ObservedObject var favoritesStore: FavoritesStore
    let onPlayGame: (Game) -> Void
    let onLoginClick: () -> Void
    let onLogsRequest: () -> Void
    let onSignOut: () -> Void
    let onShareGame: (Game) -> Void

    @StateObject private var homeVM: HomeViewModel
    @StateObject private var browseVM: BrowseViewModel
    @State private var selected: TabKey = .home
    @State private var homePath: [Game] = []
    @State private var browsePath: [Game] = []
    @State private var favoritesPath: [Game] = []
    @State private var profilePath: [ProfileRoute] = []

    init(
        catalogService: CatalogService,
        favoritesStore: FavoritesStore,
        onPlayGame: @escaping (Game) -> Void,
        onLoginClick: @escaping () -> Void,
        onLogsRequest: @escaping () -> Void,
        onSignOut: @escaping () -> Void,
        onShareGame: @escaping (Game) -> Void
    ) {
        self.catalogService = catalogService
        self.favoritesStore = favoritesStore
        self.onPlayGame = onPlayGame
        self.onLoginClick = onLoginClick
        self.onLogsRequest = onLogsRequest
        self.onSignOut = onSignOut
        self.onShareGame = onShareGame
        _homeVM = StateObject(
            wrappedValue: HomeViewModel(service: catalogService, favorites: favoritesStore)
        )
        _browseVM = StateObject(wrappedValue: BrowseViewModel(service: catalogService))
    }

    enum TabKey: String, CaseIterable, Hashable {
        case home, browse, favorites, profile
    }

    private var tabs: [UGTab] {
        [
            UGTab(key: TabKey.home.rawValue, label: "Home", systemIcon: "house.fill"),
            UGTab(key: TabKey.browse.rawValue, label: "Browse", systemIcon: "square.grid.2x2.fill"),
            UGTab(key: TabKey.favorites.rawValue, label: "Favorites", systemIcon: "heart.fill"),
            UGTab(key: TabKey.profile.rawValue, label: "Profile", systemIcon: "person.crop.circle.fill"),
        ]
    }

    private var currentPathDepth: Int {
        switch selected {
        case .home: homePath.count
        case .browse: browsePath.count
        case .favorites: favoritesPath.count
        case .profile: profilePath.count
        }
    }

    private var showTabBar: Bool { currentPathDepth == 0 }

    var body: some View {
        ZStack {
            UGColor.Surface.base.ignoresSafeArea()
            tabContent
                .animation(.easeInOut(duration: 0.18), value: selected)
            if showTabBar {
                VStack {
                    Spacer()
                    FloatingTabBar(
                        tabs: tabs,
                        selectedKey: selected.rawValue,
                        onSelect: handleTabTap
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showTabBar)
    }

    private func handleTabTap(_ rawKey: String) {
        guard let key = TabKey(rawValue: rawKey) else { return }
        if key == selected {
            popTabToRoot(key)
        } else {
            selected = key
        }
    }

    private func popTabToRoot(_ key: TabKey) {
        switch key {
        case .home: homePath.removeAll()
        case .browse: browsePath.removeAll()
        case .favorites: favoritesPath.removeAll()
        case .profile: profilePath.removeAll()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selected {
        case .home: homeStack
        case .browse: browseStack
        case .favorites: favoritesStack
        case .profile: profileStack
        }
    }

    private var homeStack: some View {
        NavigationStack(path: $homePath) {
            HomeView(
                viewModel: homeVM,
                onGameClick: { game in homePath.append(game) },
                onOpenBrowse: {
                    browsePath.removeAll()
                    selected = .browse
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        browseVM.requestSearchFocus()
                    }
                },
                onOpenBrowseFiltered: { rawCategory in
                    browsePath.removeAll()
                    browseVM.setCategoryByName(rawCategory)
                    selected = .browse
                },
                onProfileClick: { selected = .profile },
                onLogsRequest: onLogsRequest,
                onShareGame: onShareGame
            )
            .navigationDestination(for: Game.self) { game in
                gameDetailDestination(game: game, push: { homePath.append($0) })
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var browseStack: some View {
        NavigationStack(path: $browsePath) {
            BrowseView(
                viewModel: browseVM,
                onGameClick: { game in browsePath.append(game) },
                favoritesStore: favoritesStore
            )
            .navigationDestination(for: Game.self) { game in
                gameDetailDestination(game: game, push: { browsePath.append($0) })
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var favoritesStack: some View {
        NavigationStack(path: $favoritesPath) {
            FavoritesView(
                favorites: favoritesStore,
                onGameClick: { game in favoritesPath.append(game) },
                onBrowse: { selected = .browse }
            )
            .navigationDestination(for: Game.self) { game in
                gameDetailDestination(game: game, push: { favoritesPath.append($0) })
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var profileStack: some View {
        NavigationStack(path: $profilePath) {
            ProfileView(
                service: catalogService,
                showsBackButton: false,
                onBack: {},
                onLoginClick: onLoginClick,
                onLogsClick: onLogsRequest,
                onAboutClick: { profilePath.append(.about) },
                onSignOut: onSignOut
            )
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .about:
                    AboutDestination()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func gameDetailDestination(game: Game, push: @escaping (Game) -> Void) -> some View {
        GameDetailHost(
            game: game,
            catalogService: catalogService,
            favoritesStore: favoritesStore,
            onPlay: onPlayGame,
            onShare: onShareGame,
            onSimilarClick: push
        )
    }
}

private struct AboutDestination: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AboutView(onBack: { dismiss() })
            .toolbar(.hidden, for: .navigationBar)
    }
}
