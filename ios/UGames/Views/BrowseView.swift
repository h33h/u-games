import SwiftUI

struct BrowseView: View {
    @ObservedObject var viewModel: BrowseViewModel
    let onGameClick: (Game) -> Void

    @ObservedObject var favoritesStore: FavoritesStore
    @FocusState private var searchFocused: Bool
    @State private var lastTriggerGamesCount: Int = 0

    private let columns = [GridItem(.adaptive(minimum: UGSize.tileGridMin, maximum: UGSize.tileGridMax), spacing: UGSpace.l)]

    var body: some View {
        ZStack {
            UGColor.Surface.base.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if viewModel.mode == .feed && !viewModel.categories.isEmpty {
                    GenreChipRow(
                        genres: viewModel.categories.map(\.title),
                        selected: viewModel.selectedCategory?.title,
                        onSelect: { sel in
                            if let sel = sel {
                                viewModel.setCategory(viewModel.categories.first(where: { $0.title == sel }))
                            } else {
                                viewModel.setCategory(nil)
                            }
                        },
                    )
                    .padding(.top, UGSpace.s)
                }
                Spacer().frame(height: UGSpace.m)
                content
            }
        }
        .task { await viewModel.loadInitialIfNeeded() }
        .onChange(of: viewModel.searchFocusRequest) { _ in

            searchFocused = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                searchFocused = true
            }
        }
    }

    @ViewBuilder
    private var topBar: some View {
        UGSearchBarShell {
            TextField(
                "",
                text: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.searchQuery = $0 },
                ),
                prompt: Text("Search games").foregroundColor(UGColor.Text.muted),
            )
            .foregroundColor(UGColor.Text.primary)
            .submitLabel(.search)
            .onSubmit { viewModel.submitSearch() }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($searchFocused)
            if !viewModel.searchQuery.isEmpty {
                Button {
                    UGHaptics.tap()
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(UGColor.Text.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, UGSpace.m)
        .padding(.top, UGSpace.s)
    }

    @ViewBuilder
    private var content: some View {
        let visible = viewModel.visibleGames
        if visible.isEmpty && viewModel.isLoading {
            VStack { Spacer(); ProgressView().tint(UGColor.Text.primary); Spacer() }
        } else if visible.isEmpty, let err = viewModel.error {
            EmptyState(
                systemIcon: "wifi.slash",
                title: "Couldn't load",
                message: err,
                ctaLabel: "Try again",
                onCta: { Task { await viewModel.refresh() } }
            )
        } else if visible.isEmpty && viewModel.mode == .search {
            EmptyState(
                systemIcon: "magnifyingglass",
                title: "No matches",
                message: "No games match \"\(viewModel.searchQuery)\""
            )
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: UGSpace.l) {
                    ForEach(visible) { game in
                        GameCard(
                            game: game,
                            style: .tile,
                            isFavorite: favoritesStore.contains(game.appId),
                            onTap: { onGameClick(game) },
                            onFavoriteToggle: { favoritesStore.toggle(game) },
                        )
                        .onAppear {
                            if let last = visible.last, game.id == last.id,
                               viewModel.games.count != lastTriggerGamesCount {
                                lastTriggerGamesCount = viewModel.games.count
                                viewModel.loadMore()
                            }
                        }
                    }
                    if viewModel.isLoadingMore {
                        ProgressView().tint(UGColor.Text.primary).padding(UGSpace.l)
                    }
                    if !visible.isEmpty && !viewModel.hasMore && !viewModel.isLoading {
                        Text(viewModel.mode == .search ? "End of search results" : "End of catalog")
                            .font(UGFont.caption)
                            .foregroundColor(UGColor.Text.muted)
                            .padding(UGSpace.xl)
                    }
                }
                .padding(.horizontal, UGSpace.l)
                .padding(.top, UGSpace.xs)
                .padding(.bottom, UGSize.tabBarInset)
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await viewModel.refresh() }
        }
    }
}
