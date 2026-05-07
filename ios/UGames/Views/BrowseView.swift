import SwiftUI

struct BrowseView: View {
    @ObservedObject var viewModel: BrowseViewModel
    let profile: UserProfile
    let onGameClick: (Game) -> Void
    let onProfileClick: () -> Void

    @ObservedObject var favoritesStore: FavoritesStore
    @FocusState private var searchFocused: Bool
    @State private var lastTriggerGamesCount: Int = 0

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 14)]

    var body: some View {
        ZStack {
            UGColor.bg0.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if viewModel.mode == .feed && !viewModel.genres.isEmpty {
                    GenreChipRow(
                        genres: viewModel.genres,
                        selected: viewModel.selectedGenre,
                        onSelect: { viewModel.setGenre($0) },
                    )
                    .padding(.top, 8)
                }
                Spacer().frame(height: 12)
                content
            }
        }
        .task { await viewModel.loadInitialIfNeeded() }
        .onChange(of: viewModel.searchFocusRequest) { _ in
            // Tiny delay so the field is laid out before iOS will accept
            // first-responder focus.
            Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                searchFocused = true
            }
        }
    }

    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: 8) {
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

            BrowseAvatar(profile: profile, onTap: onProfileClick)
        }
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
                            // Pagination guard: only fire if the underlying
                            // games list grew since the last trigger.
                            // Otherwise a chip filter that hides every new
                            // page would keep firing loadMore on every tile
                            // tap.
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
                    if viewModel.mode == .search && !visible.isEmpty {
                        Text("End of search results")
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

private struct BrowseAvatar: View {
    let profile: UserProfile
    let onTap: () -> Void

    var body: some View {
        Group {
            if profile.isAuthorized, let url = URL(string: profile.avatarUrl), !profile.avatarUrl.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: UGColor.elevated
                    }
                }
                .frame(width: 38, height: 38)
                .clipShape(Circle())
                .overlay(Circle().stroke(LinearGradient.ugAccent, lineWidth: profile.hasYaPlus ? 2 : 0))
            } else {
                ZStack {
                    Circle().fill(UGColor.elevated)
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 22))
                        .foregroundColor(UGColor.textSecondary)
                }
                .frame(width: 38, height: 38)
            }
        }
        .contentShape(Circle())
        .onTapGesture(perform: onTap)
    }
}
