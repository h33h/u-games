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
            UGColor.bg0.ignoresSafeArea()
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
            // Two-step: drop focus first, then set it on the next runloop
            // tick. iOS won't refocus a field that's already considered
            // focused, and the @FocusState can desync after a tab switch
            // — toggling forces an actual first-responder change.
            searchFocused = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                searchFocused = true
            }
        }
    }

    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: UGSpace.s) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(UGColor.textSecondary)
            TextField(
                "",
                text: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.searchQuery = $0 },
                ),
                prompt: Text("Search games").foregroundColor(UGColor.textMuted),
            )
            .foregroundColor(UGColor.textPrimary)
            .submitLabel(.search)
            .onSubmit { viewModel.submitSearch() }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($searchFocused)
            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(UGColor.textSecondary)
                }
            }
        }
        .padding(.horizontal, UGSpace.l)
        .padding(.vertical, UGSpace.s)
        .background(UGColor.surface)
        .overlay(RoundedRectangle(cornerRadius: UGRadius.m).stroke(UGColor.divider))
        .clipShape(RoundedRectangle(cornerRadius: UGRadius.m))
        .padding(.horizontal, UGSpace.m)
        .padding(.top, UGSpace.s)
    }

    @ViewBuilder
    private var content: some View {
        let visible = viewModel.visibleGames
        if visible.isEmpty && viewModel.isLoading {
            VStack { Spacer(); ProgressView().tint(UGColor.textPrimary); Spacer() }
        } else if visible.isEmpty, let err = viewModel.error {
            VStack {
                Spacer()
                Text(err).foregroundColor(UGColor.textSecondary).font(UGFont.body).multilineTextAlignment(.center)
                Spacer()
            }
            .padding(UGSpace.xxl)
        } else if visible.isEmpty && viewModel.mode == .search {
            VStack {
                Spacer()
                Text("No games match \"\(viewModel.searchQuery)\"")
                    .foregroundColor(UGColor.textSecondary).font(UGFont.body)
                Spacer()
            }
            .padding(UGSpace.xxl)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: UGSpace.l) {
                    ForEach(visible) { game in
                        TileGameCard(
                            game: game,
                            isFavorite: favoritesStore.contains(game.appId),
                            onTap: { onGameClick(game) },
                            onFavoriteToggle: { favoritesStore.toggle(game) },
                        )
                        .onAppear {
                            // Trigger pagination once we render the last
                            // tile; the VM guards against duplicate calls.
                            if let last = visible.last, game.id == last.id,
                               viewModel.games.count != lastTriggerGamesCount {
                                lastTriggerGamesCount = viewModel.games.count
                                viewModel.loadMore()
                            }
                        }
                    }
                    if viewModel.isLoadingMore {
                        ProgressView().tint(UGColor.textPrimary).padding(UGSpace.l)
                    }
                    if !visible.isEmpty && !viewModel.hasMore && !viewModel.isLoading {
                        Text(viewModel.mode == .search ? "End of search results" : "End of catalog")
                            .font(UGFont.caption)
                            .foregroundColor(UGColor.textMuted)
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

