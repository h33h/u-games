import SwiftUI

struct CategoryGamesView: View {
    @StateObject private var viewModel: CategoryGamesViewModel
    @ObservedObject var favoritesStore: FavoritesStore
    let onGameClick: (Game) -> Void
    let onBack: () -> Void

    init(
        service: CatalogService,
        favoritesStore: FavoritesStore,
        categoryName: String,
        displayTitle: String,
        onGameClick: @escaping (Game) -> Void,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: CategoryGamesViewModel(
                service: service,
                categoryName: categoryName,
                displayTitle: displayTitle
            )
        )
        self.favoritesStore = favoritesStore
        self.onGameClick = onGameClick
        self.onBack = onBack
    }

    var body: some View {
        ZStack {
            UGColor.Surface.base.ignoresSafeArea()
            VStack(spacing: 0) {
                UGTopBar(title: viewModel.displayTitle, onBack: onBack)
                Spacer().frame(height: UGSpace.s)
                content
            }
        }
        .task { await viewModel.loadInitialIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        let visible = viewModel.games
        if visible.isEmpty && viewModel.isLoading {
            SkeletonRowList()
        } else if visible.isEmpty, let err = viewModel.error {
            EmptyState(
                systemIcon: "wifi.slash",
                title: "Couldn't load",
                message: err,
                ctaLabel: "Try again",
                onCta: { Task { await viewModel.refresh() } }
            )
        } else if visible.isEmpty {
            EmptyState(
                systemIcon: "square.grid.2x2",
                title: "No games",
                message: "There are no games in \(viewModel.displayTitle) right now."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, game in
                        GameRow(
                            game: game,
                            isFavorite: favoritesStore.contains(game.appId),
                            onTap: { onGameClick(game) },
                            onFavoriteToggle: { favoritesStore.toggle(game) }
                        )
                        if index < visible.count - 1 {
                            Divider()
                                .background(UGColor.Surface.raised)
                                .padding(.leading, UGSpace.l + UGSize.rowIcon + UGSpace.m)
                        }
                    }
                    if viewModel.hasMore {
                        Color.clear
                            .frame(height: 1)
                            .onAppear { viewModel.loadMore() }
                            .accessibilityHidden(true)
                    }
                    if viewModel.isLoadingMore {
                        ProgressView().tint(UGColor.Text.primary).padding(UGSpace.l)
                    }
                    if !visible.isEmpty && !viewModel.hasMore && !viewModel.isLoading {
                        Text("End of \(viewModel.displayTitle)")
                            .font(UGFont.caption)
                            .foregroundColor(UGColor.Text.muted)
                            .padding(UGSpace.xl)
                    }
                }
                .padding(.top, UGSpace.xs)
                .padding(.bottom, UGSpace.xl)
            }
            .refreshable { await viewModel.refresh() }
        }
    }
}

private struct GameRow: View {
    let game: Game
    let isFavorite: Bool
    let onTap: () -> Void
    let onFavoriteToggle: () -> Void

    private var iconUrl: URL? {
        URL(string: game.iconUrl(size: "pjpg256x256"))
    }

    private var halo: Color {
        Color(hex: game.iconMainColor ?? game.mainColor) ?? UGColor.Accent.primary
    }

    private var summary: String? {
        let dev = game.developer.trimmingCharacters(in: .whitespaces)
        let cats = game.categories.prefix(2).joined(separator: " · ")
        switch (dev.isEmpty, cats.isEmpty) {
        case (false, false): return "\(dev) · \(cats)"
        case (false, true):  return dev
        case (true, false):  return cats
        case (true, true):   return nil
        }
    }

    var body: some View {
        Button {
            UGHaptics.tap()
            onTap()
        } label: {
            HStack(spacing: UGSpace.m) {
                CoverImage(url: iconUrl, placeholder: halo)
                    .frame(width: UGSize.rowIcon, height: UGSize.rowIcon)
                    .clipShape(RoundedRectangle(cornerRadius: UGRadius.m))

                VStack(alignment: .leading, spacing: UGSpace.xs) {
                    Text(game.title)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundColor(UGColor.Text.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: UGSpace.xs) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(game.ratingCount > 0 ? UGColor.Accent.primary : UGColor.Text.muted)
                        if game.ratingCount > 0 {
                            Text(String(format: "%.1f", game.rating))
                                .font(UGFont.bodyS)
                                .foregroundColor(UGColor.Text.primary)
                            Text("· \(game.ratingCount) ratings")
                                .font(UGFont.bodyS)
                                .foregroundColor(UGColor.Text.muted)
                        } else {
                            Text("Not rated yet")
                                .font(UGFont.bodyS)
                                .foregroundColor(UGColor.Text.muted)
                        }
                    }

                    if let summary = summary, !summary.isEmpty {
                        Text(summary)
                            .font(UGFont.bodyS)
                            .foregroundColor(UGColor.Text.muted)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                UGCircleIconButton(
                    systemName: isFavorite ? "heart.fill" : "heart",
                    accessibilityLabel: isFavorite ? "Remove from favorites" : "Add to favorites",
                    tint: isFavorite ? UGColor.Feedback.danger : UGColor.Text.secondary,
                    diameter: UGSize.buttonSm,
                    iconSize: 14,
                    action: onFavoriteToggle
                )
            }
            .padding(.horizontal, UGSpace.l)
            .padding(.vertical, UGSpace.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(game.title)
    }
}

private struct SkeletonRowList: View {
    var count: Int = 8

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { _ in
                    HStack(spacing: UGSpace.m) {
                        Skeleton(cornerRadius: UGRadius.m)
                            .frame(width: UGSize.rowIcon, height: UGSize.rowIcon)
                        VStack(alignment: .leading, spacing: UGSpace.xs) {
                            SkeletonLine(height: 14)
                            SkeletonLine(width: 120, height: 10)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, UGSpace.l)
                    .padding(.vertical, UGSpace.s)
                }
            }
            .padding(.top, UGSpace.xs)
        }
        .disabled(true)
        .accessibilityHidden(true)
    }
}
