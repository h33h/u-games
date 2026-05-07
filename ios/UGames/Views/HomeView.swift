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
                LazyVStack(alignment: .leading, spacing: UGSpace.xl) {
                    HomeHeader(
                        profile: viewModel.profile,
                        onProfileClick: onProfileClick,
                        onProfileLongPress: onProfileLongPress,
                    )
                    .padding(.horizontal, UGSpace.l)

                    SearchStub(onTap: onOpenBrowse)
                        .padding(.horizontal, UGSpace.l)

                    if let hero = viewModel.hero {
                        HeroSection(
                            game: hero,
                            onPlay: { onGameClick(hero) },
                            onFavorite: { viewModel.toggleFavorite(hero) },
                            onShare: { onShareGame(hero) },
                        )
                        .padding(.horizontal, UGSpace.l)
                    } else {
                        Skeleton(cornerRadius: UGRadius.xl)
                            .frame(height: UGSize.heroH)
                            .padding(.horizontal, UGSpace.l)
                    }

                    if !viewModel.feedRecent.isEmpty {
                        SectionHeader(title: "My games")
                        wideRow(games: viewModel.feedRecent)
                    }

                    if let spotlight = viewModel.spotlight {
                        StoryCard(
                            title: spotlight.title,
                            subtitle: "SPOTLIGHT · \(spotlight.title.uppercased())",
                            games: Array(spotlight.games.prefix(3)),
                            onTap: { onOpenBrowseFiltered(spotlight.title) },
                        )
                        .padding(.horizontal, UGSpace.l)
                    }

                    ForEach(viewModel.genreRows, id: \.title) { row in
                        SectionHeader(
                            title: row.title,
                            seeAllAction: { onOpenBrowseFiltered(row.categoryName ?? row.title) }
                        )
                        squareRow(games: row.games)
                    }

                    if let err = viewModel.error, viewModel.hero == nil {
                        Text(err)
                            .font(UGFont.bodyS)
                            .foregroundColor(UGColor.danger)
                            .padding(.horizontal, UGSpace.l)
                    }

                    Spacer().frame(height: UGSize.tabBarInset)
                }
                .padding(.top, UGSpace.m)
            }
            .refreshable { await viewModel.refresh() }
        }
        .task { await viewModel.loadInitialIfNeeded() }
    }

    @ViewBuilder
    private func wideRow(games: [Game]) -> some View {
        // Per-item vertical padding makes each item's measured frame
        // include the halo shadow. 20pt leaves clear room for the
        // 14pt shadow + anti-alias bleed; previous 16pt was too tight.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: UGSpace.m) {
                ForEach(games) { g in
                    WideGameCard(game: g, onTap: { onGameClick(g) })
                        .padding(.vertical, UGSpace.xl)
                }
            }
            .padding(.horizontal, UGSpace.l)
        }
    }

    @ViewBuilder
    private func squareRow(games: [Game]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: UGSpace.m) {
                ForEach(games) { g in
                    SquareGameCard(game: g, onTap: { onGameClick(g) })
                        .padding(.vertical, UGSpace.xl)
                }
            }
            .padding(.horizontal, UGSpace.l)
        }
    }
}

private struct HomeHeader: View {
    let profile: UserProfile
    let onProfileClick: () -> Void
    let onProfileLongPress: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UGSpace.xs) {
            Text(eyebrow().uppercased())
                .font(UGFont.label)
                .foregroundColor(UGColor.textMuted)
            HStack {
                Text(greeting())
                    .font(UGFont.titleL)
                    .foregroundColor(UGColor.textPrimary)
                Spacer()
                UGAvatar(profile: profile)
                    .contentShape(Circle())
                    .onTapGesture(perform: onProfileClick)
                    .onLongPressGesture(minimumDuration: 0.7, perform: onProfileLongPress)
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

private struct SearchStub: View {
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: UGSpace.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(UGColor.textMuted)
            Text("Search games")
                .font(UGFont.bodyS)
                .foregroundColor(UGColor.textMuted)
            Spacer()
        }
        .padding(.horizontal, UGSpace.l)
        .padding(.vertical, UGSpace.m)
        .background(UGColor.surface)
        .overlay(RoundedRectangle(cornerRadius: UGRadius.m).stroke(UGColor.divider))
        .clipShape(RoundedRectangle(cornerRadius: UGRadius.m))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
