import SwiftUI

/// Phase 3 push screen between any catalog card and the WebView.
///
/// Layout, top to bottom:
///   1. Hero (360h): cover + mainColor halo + sticky top icons (← / ♥ / ↗)
///   2. Title block (eyebrow + DisplayXL + stat-chips)
///   3. Stats grid (Genre / Rating / Ratings)
///   4. More like this (LazyHStack of TileGameCard) — hidden on empty
///   5. Sticky bottom CTA (▶ Play now) — pulses 3 times on appearance
struct GameDetailView: View {
    @ObservedObject var viewModel: GameDetailViewModel
    @ObservedObject var favorites: FavoritesStore
    let onBack: () -> Void
    let onPlay: (Game) -> Void
    let onShare: (Game) -> Void
    let onSimilarClick: (Game) -> Void

    @State private var ctaScale: CGFloat = 1.0

    private var halo: Color { Color(hex: viewModel.game.mainColor) ?? UGColor.accent }
    private var placeholder: Color { Color(hex: viewModel.game.mainColor) ?? UGColor.elevated }

    var body: some View {
        ZStack(alignment: .bottom) {
            UGColor.bg0.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 0) {
                    hero
                    Spacer().frame(height: 20)
                    titleBlock
                    Spacer().frame(height: 18)
                    statsGrid
                    Spacer().frame(height: 24)
                    aboutSection
                    screenshotsRow
                    Spacer().frame(height: 24)
                    sectionHeader("More like this")
                    Spacer().frame(height: 12)
                    similarRow
                    Spacer().frame(height: 110)  // sticky CTA + safe area
                }
            }
            .ignoresSafeArea(edges: .top)
            stickyCta
        }
        .onAppear {
            // Pulse 3 times after appearance: each cycle 1.2s up + 1.2s
            // down, so total ≈ 7.2s. Repeat count = 6 reverse animations
            // (3 full impulses).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeInOut(duration: 1.2).repeatCount(6, autoreverses: true)) {
                    ctaScale = 1.04
                }
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .top) {
            placeholder
            GeometryReader { geo in
                // Hero is 360pt tall; the feed thumb (`pjpg250x140`)
                // looked terrible. `pjpg1280x720` is the next-largest
                // pre-rendered size on Yandex's avatars storage.
                AsyncImage(url: URL(string: viewModel.game.coverUrl(size: "pjpg1280x720"))) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    default:
                        Color.clear
                    }
                }
            }
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.30),
                    .init(color: UGColor.bg0, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            heroTopRow
                .padding(.top, 60)  // safe-area-ish; keep it static so
                .padding(.horizontal, 14)  // back button is reachable
        }
        .frame(height: 360)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(halo.opacity(UGColor.haloBorderAlpha))
                .frame(height: 0.5)
        }
        .shadow(color: halo.opacity(UGColor.haloAlpha), radius: 20, x: 0, y: 14)
    }

    private var heroTopRow: some View {
        HStack {
            heroIcon("chevron.left", action: onBack)
            Spacer()
            heroIcon(
                favorites.contains(viewModel.game.appId) ? "heart.fill" : "heart",
                tint: favorites.contains(viewModel.game.appId) ? UGColor.danger : UGColor.textPrimary,
                action: { favorites.toggle(viewModel.game) }
            )
            heroIcon("square.and.arrow.up", action: { onShare(viewModel.game) })
        }
    }

    @ViewBuilder
    private func heroIcon(
        _ system: String,
        tint: Color = UGColor.textPrimary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.55))
                .clipShape(Circle())
        }
        .buttonStyle(.borderless)
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            let eyebrow = [
                viewModel.game.categories.first?.uppercased(),
                yearFromIso(viewModel.detail?.datePublished),
            ].compactMap { $0 }.joined(separator: " · ")
            if !eyebrow.isEmpty {
                Text(eyebrow)
                    .font(UGFont.label)
                    .tracking(1.2)
                    .foregroundColor(UGColor.textMuted)
            }
            Text(viewModel.game.title)
                .font(UGFont.displayXL)
                .foregroundColor(UGColor.textPrimary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            chipsRow
        }
        .padding(.horizontal, 18)
    }

    private var chipsRow: some View {
        HStack(spacing: 6) {
            if viewModel.game.rating > 0 {
                chip(text: String(format: "★ %.1f", viewModel.game.rating), tinted: false)
            }
            if viewModel.game.ratingCount > 0 {
                chip(text: "\(viewModel.game.ratingCount) ratings", tinted: false)
            }
            chip(text: "No ads", tinted: true)
        }
    }

    private func chip(text: String, tinted: Bool) -> some View {
        Text(text)
            .font(UGFont.caption)
            .foregroundColor(tinted ? halo : UGColor.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                tinted
                ? halo.opacity(0.18)
                : Color.white.opacity(0.08)
            )
            .clipShape(Capsule())
    }

    // MARK: Stats grid

    private var statsGrid: some View {
        let genre = viewModel.game.categories.first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "—"
        let rating = viewModel.game.rating > 0 ? String(format: "★ %.1f", viewModel.game.rating) : "—"
        let ratings = viewModel.game.ratingCount > 0 ? "\(viewModel.game.ratingCount)" : "—"
        let year = yearFromIso(viewModel.detail?.datePublished)
        return HStack(spacing: 10) {
            statCard(eyebrow: "GENRE", value: genre)
            statCard(eyebrow: "RATING", value: rating)
            // Show release year when JSON-LD provides one; otherwise fall
            // back to the rating count (next-most-honest stat we have).
            if let year = year {
                statCard(eyebrow: "RELEASED", value: year)
            } else {
                statCard(eyebrow: "RATINGS", value: ratings)
            }
        }
        .padding(.horizontal, 18)
    }

    private func yearFromIso(_ iso: String?) -> String? {
        guard let iso = iso, !iso.isEmpty else { return nil }
        let first4 = iso.prefix(4)
        return first4.count == 4 && first4.allSatisfy { $0.isNumber } ? String(first4) : nil
    }

    // MARK: About + screenshots (from JSON-LD on the per-app page)

    @ViewBuilder
    private var aboutSection: some View {
        let description = viewModel.detail?.description
        if let text = description, !text.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("ABOUT")
                    .font(UGFont.label)
                    .tracking(1.2)
                    .foregroundColor(UGColor.textMuted)
                Text(text)
                    .font(UGFont.body)
                    .foregroundColor(UGColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        } else if viewModel.isLoadingDetail {
            VStack(alignment: .leading, spacing: 8) {
                Text("ABOUT")
                    .font(UGFont.label)
                    .tracking(1.2)
                    .foregroundColor(UGColor.textMuted)
                ForEach(0..<3) { _ in
                    Skeleton(cornerRadius: 4).frame(height: 12)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var screenshotsRow: some View {
        let urls = viewModel.detail?.screenshots ?? []
        if !urls.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("SCREENSHOTS")
                    .font(UGFont.label)
                    .tracking(1.2)
                    .foregroundColor(UGColor.textMuted)
                    .padding(.horizontal, 18)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(urls, id: \.self) { url in
                            screenshotTile(url: url)
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
        } else if viewModel.isLoadingDetail {
            VStack(alignment: .leading, spacing: 10) {
                Text("SCREENSHOTS")
                    .font(UGFont.label)
                    .tracking(1.2)
                    .foregroundColor(UGColor.textMuted)
                    .padding(.horizontal, 18)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<3) { _ in
                            Skeleton(cornerRadius: 16)
                                .frame(width: 220, height: 124)
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
    }

    private func screenshotTile(url: String) -> some View {
        ZStack {
            UGColor.elevated
            GeometryReader { geo in
                AsyncImage(url: URL(string: url)) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    default:
                        Color.clear
                    }
                }
            }
        }
        .frame(width: 220, height: 124)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(halo.opacity(UGColor.haloBorderAlpha)))
        .shadow(color: halo.opacity(UGColor.haloAlpha), radius: 12, x: 0, y: 8)
    }

    private func statCard(eyebrow: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(UGFont.label)
                .tracking(1.2)
                .foregroundColor(UGColor.textMuted)
            Text(value)
                .font(UGFont.titleM)
                .foregroundColor(UGColor.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(UGColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(UGFont.titleM)
                .foregroundColor(UGColor.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 18)
    }

    // MARK: Similar row

    @ViewBuilder
    private var similarRow: some View {
        if viewModel.isLoadingSimilar {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<3) { _ in
                        Skeleton(cornerRadius: 16)
                            .frame(width: 160, height: 140)
                    }
                }
                .padding(.horizontal, 18)
            }
        } else if viewModel.similar.isEmpty {
            if viewModel.similarError != nil {
                Text("Couldn't load related games")
                    .font(UGFont.bodyS)
                    .foregroundColor(UGColor.textMuted)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                EmptyView()
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(viewModel.similar, id: \.appId) { g in
                        TileGameCard(
                            game: g,
                            isFavorite: favorites.contains(g.appId),
                            onTap: { onSimilarClick(g) },
                            onFavoriteToggle: { favorites.toggle(g) }
                        )
                        .frame(width: 160)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    // MARK: Sticky CTA

    private var stickyCta: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: UGColor.bg0.opacity(0.6), location: 0.3),
                    .init(color: UGColor.bg0, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 100)
            .allowsHitTesting(false)
            Button(action: { onPlay(viewModel.game) }) {
                Text("▶ Play now")
                    .font(UGFont.bodyS.weight(.heavy))
                    .foregroundColor(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(LinearGradient.ugAccent)
                    .clipShape(Capsule())
                    .shadow(color: UGColor.accent.opacity(0.5), radius: 18, x: 0, y: 8)
                    .scaleEffect(ctaScale)
            }
            .buttonStyle(.borderless)
            .padding(.bottom, 18)
            .background(UGColor.bg0)
        }
        .frame(maxWidth: .infinity)
    }
}
