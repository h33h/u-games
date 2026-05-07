import SwiftUI

struct BrowseView: View {
    @ObservedObject var viewModel: BrowseViewModel
    let onGameClick: (Game) -> Void

    @ObservedObject var favoritesStore: FavoritesStore
    @FocusState private var searchFocused: Bool
    @State private var lastTriggerGamesCount: Int = 0

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 14)]

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
                    .padding(.top, 8)
                }
                Spacer().frame(height: 12)
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
        HStack(spacing: 8) {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(UGColor.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(UGColor.divider))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 12)
        .padding(.top, 8)
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
            .padding(24)
        } else if visible.isEmpty && viewModel.mode == .search {
            VStack {
                Spacer()
                Text("No games match \"\(viewModel.searchQuery)\"")
                    .foregroundColor(UGColor.textSecondary).font(UGFont.body)
                Spacer()
            }
            .padding(24)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
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
                        ProgressView().tint(UGColor.textPrimary).padding(16)
                    }
                    if !visible.isEmpty && !viewModel.hasMore && !viewModel.isLoading {
                        Text(viewModel.mode == .search ? "End of search results" : "End of catalog")
                            .font(UGFont.caption)
                            .foregroundColor(UGColor.textMuted)
                            .padding(20)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await viewModel.refresh() }
        }
    }
}

