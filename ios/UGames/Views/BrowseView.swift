import SwiftUI

struct BrowseView: View {
    @ObservedObject var viewModel: BrowseViewModel
    let profile: UserProfile
    let onGameClick: (Game) -> Void
    let onProfileClick: () -> Void

    @ObservedObject var favoritesStore: FavoritesStore

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)]

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
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(visible) { game in
                        TileGameCard(
                            game: game,
                            isFavorite: favoritesStore.contains(game.appId),
                            onTap: { onGameClick(game) },
                            onFavoriteToggle: { favoritesStore.toggle(game) },
                        )
                        .onAppear {
                            // Trigger pagination ~6 tiles before the end of the
                            // visible window. Match Android's threshold.
                            if let last = visible.last, game.id == last.id {
                                viewModel.loadMore()
                            }
                        }
                    }
                    if viewModel.isLoadingMore {
                        ProgressView().tint(UGColor.textPrimary).padding(16)
                    }
                }
                .padding(.horizontal, 12)
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
