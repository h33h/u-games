import SwiftUI

struct CatalogView: View {
    @ObservedObject var service: CatalogService
    let onGameClick: (Game) -> Void
    let onLoginClick: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

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
                    onLoginClick: onLoginClick
                )
                contentView
            }
        }
        .task { await service.loadInitial() }
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
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(service.games) { game in
                        GameCard(game: game)
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
        }
    }
}

struct CatalogTopBar: View {
    @Binding var query: String
    let profile: UserProfile
    let onSubmit: () -> Void
    let onLoginClick: () -> Void

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

            ProfileButton(profile: profile, onClick: onLoginClick)
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

private struct GameCard: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: game.coverUrl)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: Color(white: 0.1)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

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
