import SwiftUI

/// Phase-2 tab container. Hosts Home / Browse / Favorites / Profile and a
/// per-tab About push (Profile-only for this phase). Game / Auth / Logs are
/// driven by the parent `RootView` global route — Phase 3 will move them
/// into per-tab stacks.
///
/// `hideBar` is set externally when the parent route is non-`.catalog`, and
/// also toggles internally while About is pushed.
struct TabContainer: View {
    @ObservedObject var catalogService: CatalogService
    @ObservedObject var recentStore: RecentGamesStore
    @ObservedObject var favoritesStore: FavoritesStore
    let onLogsRequest: () -> Void
    let onGameOpen: (Game) -> Void
    let onLoginClick: () -> Void
    let onSignOut: () -> Void

    @StateObject private var homeVM: HomeViewModel
    @StateObject private var browseVM: BrowseViewModel
    @State private var selected: String = "home"
    @State private var aboutPresented: Bool = false

    init(
        catalogService: CatalogService,
        recentStore: RecentGamesStore,
        favoritesStore: FavoritesStore,
        onLogsRequest: @escaping () -> Void,
        onGameOpen: @escaping (Game) -> Void,
        onLoginClick: @escaping () -> Void,
        onSignOut: @escaping () -> Void,
    ) {
        self.catalogService = catalogService
        self.recentStore = recentStore
        self.favoritesStore = favoritesStore
        self.onLogsRequest = onLogsRequest
        self.onGameOpen = onGameOpen
        self.onLoginClick = onLoginClick
        self.onSignOut = onSignOut
        _homeVM = StateObject(
            wrappedValue: HomeViewModel(
                service: catalogService,
                recents: recentStore,
                favorites: favoritesStore,
            )
        )
        _browseVM = StateObject(wrappedValue: BrowseViewModel(service: catalogService))
    }

    private let tabs: [UGTab] = [
        .init(key: "home", label: "Home", systemIcon: "house.fill"),
        .init(key: "browse", label: "Browse", systemIcon: "square.grid.2x2.fill"),
        .init(key: "favorites", label: "Favorites", systemIcon: "heart.fill"),
        .init(key: "profile", label: "Profile", systemIcon: "person.crop.circle.fill"),
    ]

    var body: some View {
        ZStack {
            UGColor.bg0.ignoresSafeArea()
            switch selected {
            case "home":
                HomeView(
                    viewModel: homeVM,
                    onGameClick: onGameOpen,
                    onOpenBrowse: { selected = "browse" },
                    onOpenBrowseFiltered: { genre in
                        browseVM.setGenre(genre)
                        selected = "browse"
                    },
                    onProfileClick: { selected = "profile" },
                    onProfileLongPress: onLogsRequest,
                    onShareGame: { _ in /* phase 3: UIActivityViewController */ },
                )
            case "browse":
                BrowseView(
                    viewModel: browseVM,
                    profile: catalogService.profile,
                    onGameClick: onGameOpen,
                    onProfileClick: { selected = "profile" },
                    favoritesStore: favoritesStore,
                )
            case "favorites":
                FavoritesView(
                    favorites: favoritesStore,
                    onGameClick: onGameOpen,
                    onBrowse: { selected = "browse" },
                )
            case "profile":
                if aboutPresented {
                    AboutView(onBack: { aboutPresented = false })
                } else {
                    ProfileView(
                        service: catalogService,
                        onLoginClick: onLoginClick,
                        onLogsClick: onLogsRequest,
                        onAboutClick: { aboutPresented = true },
                        onSignOut: onSignOut,
                    )
                }
            default:
                EmptyView()
            }
            if !(selected == "profile" && aboutPresented) {
                VStack {
                    Spacer()
                    FloatingTabBar(
                        tabs: tabs,
                        selectedKey: selected,
                        onSelect: { key in
                            selected = key
                            // Switching away from Profile resets About so it
                            // doesn't ghost-render the next time the user
                            // returns.
                            if key != "profile" { aboutPresented = false }
                        },
                    )
                }
            }
        }
    }

    func refreshAfterAuth() {
        Task {
            await homeVM.refresh()
            await catalogService.refreshProfile()
        }
    }
}
