import SwiftUI

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
            UGColor.Surface.base.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: UGSpace.xl) {
                    HomeHeader(
                        profile: viewModel.profile,
                        onProfileClick: onProfileClick,
                        onProfileLongPress: onProfileLongPress,
                    )
                    .padding(.horizontal, UGSpace.l)

                    UGSearchBarShell {
                        Text("Search games")
                            .font(UGFont.bodyS)
                            .foregroundColor(UGColor.Text.muted)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpenBrowse)
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
                            .foregroundColor(UGColor.Feedback.danger)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: UGSpace.m) {
                ForEach(games) { g in
                    GameCard(game: g, style: .wide, onTap: { onGameClick(g) })
                        .padding(.vertical, UGSpace.xxxl)
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
                    GameCard(game: g, style: .square, onTap: { onGameClick(g) })
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
                .foregroundColor(UGColor.Text.muted)
            HStack {
                Text(greeting())
                    .font(UGFont.titleL)
                    .foregroundColor(UGColor.Text.primary)
                Spacer()
                UGAvatar(profile: profile)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UGHaptics.tap()
                        onProfileClick()
                    }
                    .onLongPressGesture(minimumDuration: 0.7) {
                        UGHaptics.selection()
                        onProfileLongPress()
                    }
                    .accessibilityLabel("Open profile")
                    .accessibilityHint("Long press for diagnostic logs")
                    .accessibilityAddTraits(.isButton)
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
