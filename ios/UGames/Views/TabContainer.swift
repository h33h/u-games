import SwiftUI

/// Phase 1 tab container. Home renders the existing CatalogView via the
/// passed-in `home` ViewBuilder; other tabs are EmptyState("Coming soon").
/// `hideBar` is true while caller pushes Game/Auth/Logs above the container.
struct TabContainer<HomeContent: View>: View {
    let hideBar: Bool
    @ViewBuilder let home: () -> HomeContent

    @State private var selected: String = "home"

    private let tabs: [UGTab] = [
        .init(key: "home", label: "Home", systemIcon: "house.fill"),
        .init(key: "browse", label: "Browse", systemIcon: "square.grid.2x2.fill"),
        .init(key: "favorites", label: "Favorites", systemIcon: "heart.fill"),
        .init(key: "profile", label: "Profile", systemIcon: "person.crop.circle.fill"),
    ]

    var body: some View {
        ZStack {
            switch selected {
            case "home":
                home()
            case "browse":
                EmptyState(systemIcon: "square.grid.2x2", title: "Browse — coming soon", message: "Genre filters and sort will land here.")
            case "favorites":
                EmptyState(systemIcon: "heart", title: "Favorites — coming soon", message: "Saved games will live here.")
            case "profile":
                EmptyState(systemIcon: "person.crop.circle", title: "Profile — coming soon", message: "Sign in / Plus / Logs.")
            default:
                EmptyView()
            }
            if !hideBar {
                VStack {
                    Spacer()
                    FloatingTabBar(tabs: tabs, selectedKey: selected, onSelect: { selected = $0 })
                }
            }
        }
    }
}
