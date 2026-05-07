import SwiftUI

/// Editorial Home screen. Single ScrollView, sections separated by
/// uniform spacing. Header (eyebrow + greeting + avatar) flows under
/// the status bar so the Hero card sets the visual tone immediately.
struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    let onGameClick: (Game) -> Void
    let onOpenBrowse: () -> Void
    let onOpenBrowseFiltered: (String) -> Void
    let onProfileClick: () -> Void
    let onProfileLongPress: () -> Void
    let onShareGame: (Game) -> Void

    var body: some View {
        ZStack {
            UGColor.bg0.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    HomeHeader(
                        profile: viewModel.profile,
                        onProfileClick: onProfileClick,
                        onProfileLongPress: onProfileLongPress,
                    )
                    .padding(.horizontal, 14)

                    SearchStub(onTap: onOpenBrowse)
                        .padding(.horizontal, 14)

                    if let hero = viewModel.hero {
                        HeroSection(
                            game: hero,
                            onPlay: { onGameClick(hero) },
                            onFavorite: { viewModel.toggleFavorite(hero) },
                            onShare: { onShareGame(hero) },
                        )
                        .padding(.horizontal, 14)
                    } else {
                        Skeleton(cornerRadius: 22)
                            .frame(height: 300)
                            .padding(.horizontal, 14)
                    }

                    if !viewModel.feedRecent.isEmpty {
                        sectionHeader(title: "My games", showAll: false, onSeeAll: {})
                        wideRow(games: viewModel.feedRecent)
                    }

                    if let spotlight = viewModel.spotlight {
                        StoryCard(
                            title: spotlight.title,
                            subtitle: "SPOTLIGHT · \(spotlight.title.uppercased())",
                            games: Array(spotlight.games.prefix(3)),
                            onTap: { onOpenBrowseFiltered(spotlight.title) },
                        )
                        .padding(.horizontal, 14)
                    }

                    ForEach(viewModel.genreRows, id: \.title) { row in
                        sectionHeader(
                            title: row.title,
                            showAll: true,
                            onSeeAll: { onOpenBrowseFiltered(row.categoryName ?? row.title) },
                        )
                        squareRow(games: row.games)
                    }

                    if let err = viewModel.error, viewModel.hero == nil {
                        Text(err)
                            .font(UGFont.bodyS)
                            .foregroundColor(UGColor.danger)
                            .padding(.horizontal, 14)
                    }

                    Spacer().frame(height: 96)
                }
                .padding(.top, 12)
            }
            .refreshable { await viewModel.refresh() }
        }
        .task { await viewModel.loadInitialIfNeeded() }
    }

    @ViewBuilder
    private func sectionHeader(title: String, showAll: Bool, onSeeAll: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(UGFont.titleM)
                .foregroundColor(UGColor.textPrimary)
            Spacer()
            if showAll {
                Button(action: onSeeAll) {
                    HStack(spacing: 2) {
                        Text("See all")
                            .font(UGFont.bodyS)
                            .foregroundColor(UGColor.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(UGColor.textSecondary)
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func wideRow(games: [Game]) -> some View {
        // Vertical padding so each card's mainColor halo (12pt shadow)
        // has breathing room. Without it the halo is vertically
        // clipped by the row's measured frame.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(games) { g in
                    WideGameCard(game: g, onTap: { onGameClick(g) })
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    private func squareRow(games: [Game]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(games) { g in
                    SquareGameCard(game: g, onTap: { onGameClick(g) })
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }
}

private struct HomeHeader: View {
    let profile: UserProfile
    let onProfileClick: () -> Void
    let onProfileLongPress: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow().uppercased())
                .font(UGFont.label)
                .foregroundColor(UGColor.textMuted)
            HStack {
                Text(greeting())
                    .font(UGFont.titleL)
                    .foregroundColor(UGColor.textPrimary)
                Spacer()
                ProfileAvatar(
                    profile: profile,
                    onTap: onProfileClick,
                    onLongPress: onProfileLongPress,
                )
            }
        }
    }

    private func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case ..<12: return "Good morning"
        case ..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private func eyebrow() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let day = formatter.string(from: Date())
        return "\(day) · Top picks"
    }
}

private struct ProfileAvatar: View {
    let profile: UserProfile
    let onTap: () -> Void
    let onLongPress: () -> Void

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
                .overlay(
                    Circle().stroke(LinearGradient.ugAccent, lineWidth: profile.hasYaPlus ? 2 : 0)
                )
            } else {
                ZStack {
                    Circle().fill(UGColor.elevated)
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(UGColor.textSecondary)
                }
                .frame(width: 38, height: 38)
            }
        }
        .contentShape(Circle())
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.7, perform: onLongPress)
    }
}

private struct SearchStub: View {
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(UGColor.textMuted)
            Text("Search games")
                .font(UGFont.bodyS)
                .foregroundColor(UGColor.textMuted)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(UGColor.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(UGColor.divider))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
