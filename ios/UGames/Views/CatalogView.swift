import SwiftUI

struct CatalogView: View {
    @ObservedObject var service: CatalogService
    @ObservedObject var recentStore: RecentGamesStore
    @ObservedObject var favoritesStore: FavoritesStore
    let onGameClick: (Game) -> Void
    let onLoginClick: () -> Void

    @State private var profileSheetPresented = false

    // Adaptive grid: at least 2 columns on phones (390pt → 2×~170pt cards),
    // up to 4 on iPad / landscape (744pt+ → 4 columns of ~170pt each).
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                CatalogTopBar(
                    query: Binding(
                        get: { service.searchQuery },
                        set: { service.searchQuery = $0 }
                    ),
                    profile: service.profile,
                    onSubmit: { service.submitSearch() },
                    onProfileClick: {
                        if service.profile.isAuthorized {
                            profileSheetPresented = true
                        } else {
                            onLoginClick()
                        }
                    }
                )
                contentView
            }
        }
        .task { await service.loadInitial() }
        .sheet(isPresented: $profileSheetPresented) {
            ProfileSheet(
                profile: service.profile,
                onSignOut: {
                    profileSheetPresented = false
                    Task { await service.clearSession() }
                },
                onClose: { profileSheetPresented = false }
            )
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if service.games.isEmpty && service.isLoading {
            Spacer()
            ProgressView().tint(.white)
            Spacer()
        } else if service.games.isEmpty, let err = service.error {
            Spacer()
            VStack(spacing: 16) {
                Text(err).foregroundColor(.white).multilineTextAlignment(.center)
                Button("Retry") { Task { await service.refreshFeed() } }
                    .buttonStyle(.borderedProminent)
            }.padding(24)
            Spacer()
        } else if service.games.isEmpty && service.mode == .search {
            Spacer()
            Text("No games match \"\(service.searchQuery)\"")
                .foregroundColor(.white)
                .padding()
            Spacer()
        } else {
            ScrollView {
                if !favoritesStore.games.isEmpty && service.mode == .feed {
                    HorizontalGameRow(
                        title: "Favorites",
                        games: favoritesStore.games,
                        onClick: onGameClick
                    )
                    .padding(.top, 8)
                }
                if !recentStore.games.isEmpty && service.mode == .feed {
                    HorizontalGameRow(
                        title: "Recently played",
                        games: recentStore.games,
                        onClick: onGameClick
                    )
                    .padding(.top, 8)
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(service.games) { game in
                        GameCard(
                            game: game,
                            isFavorite: favoritesStore.contains(game.appId),
                            onFavoriteToggle: { favoritesStore.toggle(game) }
                        )
                            .onTapGesture { onGameClick(game) }
                            .onAppear {
                                if let last = service.games.last,
                                   game.id == last.id {
                                    service.loadMore()
                                }
                            }
                    }
                }
                .padding(12)
                if service.isLoadingMore {
                    ProgressView().tint(.white).padding(16)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await service.refreshFeed() }
        }
    }
}

struct CatalogTopBar: View {
    @Binding var query: String
    let profile: UserProfile
    let onSubmit: () -> Void
    let onProfileClick: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color(white: 0.65))
                TextField("", text: $query, prompt: Text("Search games").foregroundColor(Color(white: 0.5)))
                    .foregroundColor(.white)
                    .submitLabel(.search)
                    .onSubmit(onSubmit)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(white: 0.5))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(white: 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            ProfileButton(profile: profile, onClick: onProfileClick)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

private struct ProfileButton: View {
    let profile: UserProfile
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            if profile.isAuthorized, let url = URL(string: profile.avatarUrl), !profile.avatarUrl.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color(white: 0.2)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundColor(.white)
            }
        }
    }
}

private struct HorizontalGameRow: View {
    let title: String
    let games: [Game]
    let onClick: (Game) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(games) { game in
                        VStack(alignment: .leading, spacing: 4) {
                            AsyncImage(url: URL(string: game.iconUrl.isEmpty ? game.coverUrl : game.iconUrl)) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: Color(white: 0.1)
                                }
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(game.title)
                                .foregroundColor(.white)
                                .font(.caption)
                                .lineLimit(2)
                                .frame(width: 100, alignment: .leading)
                        }
                        .onTapGesture { onClick(game) }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct GameCard: View {
    let game: Game
    let isFavorite: Bool
    let onFavoriteToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: game.coverUrl)) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color(white: 0.1)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button(action: onFavoriteToggle) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isFavorite ? Color(red: 1.0, green: 0.3, blue: 0.4) : .white)
                        .padding(7)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                }
                .padding(6)
                // Stop the tap from also launching the game.
                .buttonStyle(.borderless)
            }

            Text(game.title)
                .foregroundColor(.white)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

            if game.ratingCount > 0 {
                Text(String(format: "★ %.1f", game.rating))
                    .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.0))
                    .font(.caption)
            }
        }
        .padding(8)
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct ProfileSheet: View {
    let profile: UserProfile
    let onSignOut: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(Color(white: 0.6))
                }
            }
            VStack(spacing: 8) {
                if let url = URL(string: profile.avatarUrl), !profile.avatarUrl.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Color(white: 0.2)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 72, height: 72)
                        .foregroundColor(Color(white: 0.4))
                }
                Text(profile.displayName.isEmpty ? profile.login : profile.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                if !profile.login.isEmpty && profile.displayName != profile.login {
                    Text(profile.login)
                        .font(.subheadline)
                        .foregroundColor(Color(white: 0.6))
                }
                if profile.hasYaPlus {
                    Text("Yandex Plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(red: 1.0, green: 0.78, blue: 0.0).opacity(0.2))
                        .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.0))
                        .clipShape(Capsule())
                }
            }
            Spacer()
            Button(role: .destructive, action: onSignOut) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Sign out")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(white: 0.15))
                .foregroundColor(.red)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}
