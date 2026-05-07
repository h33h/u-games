import SwiftUI

/// Phase-2 tab container. Hosts Home / Browse / Favorites tabs; Profile is
/// pushed from the avatar in Home/Browse top-bars. About is a sub-push
/// from Profile. Game / Auth / Logs still live at the parent `RootView`
/// level — phase 3 may move them in.
///
/// Tab-bar hides whenever a "pushed" view (Profile or About) is on screen.
struct TabContainer: View {
    @ObservedObject var catalogService: CatalogService
    @ObservedObject var favoritesStore: FavoritesStore
    let onLogsRequest: () -> Void
    let onGameOpen: (Game) -> Void
    let onLoginClick: () -> Void
    let onSignOut: () -> Void

    @StateObject private var homeVM: HomeViewModel
    @StateObject private var browseVM: BrowseViewModel
    @State private var selected: String = "home"
    @State private var profilePresented: Bool = false
    @State private var aboutPresented: Bool = false

    init(
        catalogService: CatalogService,
        favoritesStore: FavoritesStore,
        onLogsRequest: @escaping () -> Void,
        onGameOpen: @escaping (Game) -> Void,
        onLoginClick: @escaping () -> Void,
        onSignOut: @escaping () -> Void,
    ) {
        self.catalogService = catalogService
        self.favoritesStore = favoritesStore
        self.onLogsRequest = onLogsRequest
        self.onGameOpen = onGameOpen
        self.onLoginClick = onLoginClick
        self.onSignOut = onSignOut
        _homeVM = StateObject(
            wrappedValue: HomeViewModel(
                service: catalogService,
                favorites: favoritesStore,
            )
        )
        _browseVM = StateObject(wrappedValue: BrowseViewModel(service: catalogService))
    }

    private let tabs: [UGTab] = [
        .init(key: "home", label: "Home", systemIcon: "house.fill"),
        .init(key: "browse", label: "Browse", systemIcon: "square.grid.2x2.fill"),
        .init(key: "favorites", label: "Favorites", systemIcon: "heart.fill"),
    ]

    var body: some View {
        ZStack {
            UGColor.bg0.ignoresSafeArea()
            tabContent
            if profilePresented {
                if aboutPresented {
                    AboutView(onBack: { aboutPresented = false })
                        .transition(.opacity)
                } else {
                    ProfileView(
                        service: catalogService,
                        onBack: { profilePresented = false },
                        onLoginClick: {
                            profilePresented = false
                            onLoginClick()
                        },
                        onLogsClick: {
                            profilePresented = false
                            onLogsRequest()
                        },
                        onAboutClick: { aboutPresented = true },
                        onSignOut: {
                            onSignOut()
                            profilePresented = false
                        },
                    )
                    .transition(.opacity)
                }
            }
            if !profilePresented {
                VStack {
                    Spacer()
                    FloatingTabBar(
                        tabs: tabs,
                        selectedKey: selected,
                        onSelect: { selected = $0 },
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selected {
        case "home":
            HomeView(
                viewModel: homeVM,
                onGameClick: onGameOpen,
                onOpenBrowse: {
                    selected = "browse"
                    // Bump focus AFTER the tab switch so BrowseView is on
                    // screen by the time @FocusState becomes true.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        browseVM.requestSearchFocus()
                    }
                },
                onOpenBrowseFiltered: { rawCategory in
                    browseVM.setCategoryByName(rawCategory)
                    selected = "browse"
                },
                onProfileClick: { profilePresented = true },
                onProfileLongPress: onLogsRequest,
                onShareGame: { _ in /* phase 3 */ },
            )
        case "browse":
            BrowseView(
                viewModel: browseVM,
                onGameClick: onGameOpen,
                favoritesStore: favoritesStore,
            )
        case "favorites":
            FavoritesView(
                favorites: favoritesStore,
                onGameClick: onGameOpen,
                onBrowse: { selected = "browse" },
            )
        default:
            EmptyView()
        }
    }
}
