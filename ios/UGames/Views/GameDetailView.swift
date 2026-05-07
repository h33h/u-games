import SwiftUI

/// Phase 3 push screen between any catalog card and the WebView. Every
/// field is real data from the feed item or JSON-LD; nothing is
/// fabricated and no two sections show the same fact twice.
///
/// Sections (top to bottom):
///   1. Hero (360h): hi-res cover + mainColor halo + sticky ← / ♥ / ↗
///   2. Title block — eyebrow (genre · year), DisplayXL title, "by
///      {developer}" line, chips (rating · count, age) — chips only
///      render fields that exist; no fakes.
///   3. About paragraph — JSON-LD `mainEntityOfPage.description`
///   4. Screenshots — JSON-LD `screenshot[]`
///   5. More like this — `similar_games` endpoint
///   6. Information — key/value rows for the long-tail metadata that
///      doesn't fit a chip (full genre list, languages, developer
///      again-but-formatted, release date)
///
/// Plus a sticky bottom CTA (▶ Play now) with a 3-impulse pulse.
struct GameDetailView: View {
    @ObservedObject var viewModel: GameDetailViewModel
    @ObservedObject var favorites: FavoritesStore
    let onBack: () -> Void
    let onPlay: (Game) -> Void
    let onShare: (Game) -> Void
    let onSimilarClick: (Game) -> Void

    @State private var ctaScale: CGFloat = 1.0
    /// `nil` when the screenshot viewer is closed; otherwise the
    /// initial page index. Wrapped in an Identifiable struct because
    /// `.fullScreenCover(item:)` needs that.
    @State private var fullscreen: ScreenshotPager?

    /// Total height of the CTA gradient strip. ScrollView's bottom
    /// inset matches this so the Information block scrolls fully into
    /// view above the strip instead of fading under it. The gradient
    /// itself fades transparent → bg0 by ~55%, leaving the bottom
    /// half opaque (covering the button + home-indicator area) but
    /// without a visible "panel" seam.
    private let ctaStripHeight: CGFloat = 170

    private var halo: Color { Color(hex: viewModel.game.mainColor) ?? UGColor.accent }
    private var placeholder: Color { Color(hex: viewModel.game.mainColor) ?? UGColor.elevated }

    var body: some View {
        // GeometryReader extends past the safe area on every edge so
        // we can read `proxy.safeAreaInsets.{top,bottom}` and lay out
        // (a) the sticky top icons just below the status bar, and
        // (b) the gradient strip into the home-indicator zone.
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom
            ZStack(alignment: .bottom) {
                UGColor.bg0
                ScrollView {
                    LazyVStack(spacing: 0) {
                        hero
                        Spacer().frame(height: 20)
                        titleBlock
                        Spacer().frame(height: 24)
                        aboutSection
                        screenshotsRow
                        Spacer().frame(height: 24)
                        sectionHeader("More like this")
                        Spacer().frame(height: 12)
                        similarRow
                        Spacer().frame(height: 24)
                        informationBlock
                        // Bottom inset matches the sticky CTA strip
                        // (gradient + safe area) so the Information
                        // block can scroll fully into view above the
                        // gradient instead of fading under it.
                        Spacer().frame(height: ctaStripHeight + safeBottom)
                    }
                }
                .ignoresSafeArea(edges: .top)
                stickyCta(safeBottom: safeBottom)
                // Sticky top controls — anchored to the screen top so
                // they stay visible/tappable while the hero scrolls.
                heroTopRow
                    .padding(.top, max(safeTop, 44) + 8)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea()
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
        .fullScreenCover(item: $fullscreen) { pager in
            ScreenshotsFullscreenView(
                screenshots: viewModel.detail?.screenshots ?? [],
                initialIndex: pager.index,
                onDismiss: { fullscreen = nil }
            )
        }
    }

    // MARK: Hero

    private var hero: some View {
        // Stretchy header: when the user pulls down past the top, the
        // ScrollView rubber-bands content downward — leaving a gap
        // above the hero. We fill that gap by stretching the cover
        // image upward so the screen always shows artwork instead of
        // bg0. Top controls (Back / Heart / Share) are NOT inside the
        // hero — they live as a screen-level overlay so they stay
        // sticky while the hero scrolls.
        ZStack(alignment: .top) {
            stretchyCover
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.30),
                    .init(color: UGColor.bg0, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
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

    /// Cover image that grows upward when the parent ScrollView is
    /// rubber-banded down. `.global` minY of the geometry reader
    /// equals the hero's screen Y position; when overscrolled at the
    /// top it becomes positive, and we feed that into the image's
    /// height + a matching upward offset so the image fills the gap.
    private var stretchyCover: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .global).minY
            let stretch = max(0, minY)
            ZStack {
                placeholder
                CachedAsyncImage(url: URL(string: viewModel.game.coverUrl(size: "pjpg1280x720"))) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Color.clear
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height + stretch)
            .clipped()
            .offset(y: -stretch)
        }
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
            // Eyebrow combines anything we have: first genre + release
            // year. Both fields are honest data — no hardcoded suffix.
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
            if let author = pickAuthor() {
                Text("by \(author)")
                    .font(UGFont.bodyS)
                    .foregroundColor(UGColor.textSecondary)
                    .lineLimit(1)
            }
            chipsRow
        }
        .padding(.horizontal, 18)
    }

    @ViewBuilder
    private var chipsRow: some View {
        let chips = buildChips()
        if !chips.isEmpty {
            HStack(spacing: 6) {
                ForEach(chips, id: \.self) { c in
                    chip(text: c)
                }
            }
        }
    }

    private func buildChips() -> [String] {
        var out: [String] = []
        if viewModel.game.rating > 0 {
            var s = String(format: "★ %.1f", viewModel.game.rating)
            if viewModel.game.ratingCount > 0 {
                s += " · " + formatCount(viewModel.game.ratingCount)
            }
            out.append(s)
        } else if viewModel.game.ratingCount > 0 {
            out.append("\(formatCount(viewModel.game.ratingCount)) ratings")
        }
        if let age = viewModel.game.ageRating, !age.isEmpty {
            out.append(age)
        }
        return out
    }

    private func chip(text: String) -> some View {
        Text(text)
            .font(UGFont.caption)
            .foregroundColor(UGColor.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
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
                        ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                            screenshotTile(url: url)
                                .onTapGesture { fullscreen = ScreenshotPager(index: idx) }
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
                CachedAsyncImage(url: URL(string: url)) { phase in
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

    // MARK: Information block

    @ViewBuilder
    private var informationBlock: some View {
        // Build the rows from real data only — every empty source
        // collapses its own row so the section silently shrinks instead
        // of showing "—" placeholders. The full genre list goes here
        // (the eyebrow only had room for the first genre); language
        // list is JSON-LD-only; developer is the catalog's value,
        // formatted as a row instead of floating loose under the title.
        let rows = buildInfoRows()
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("INFORMATION")
                    .font(UGFont.label)
                    .tracking(1.2)
                    .foregroundColor(UGColor.textMuted)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                        if idx > 0 {
                            Rectangle()
                                .fill(UGColor.divider)
                                .frame(height: 1)
                                .frame(maxWidth: .infinity)
                        }
                        HStack(alignment: .top) {
                            Text(row.label)
                                .font(UGFont.bodyS)
                                .foregroundColor(UGColor.textMuted)
                                .frame(width: 110, alignment: .leading)
                            Text(row.value)
                                .font(UGFont.bodyS)
                                .foregroundColor(UGColor.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                }
                .background(UGColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 18)
        }
    }

    private func buildInfoRows() -> [(label: String, value: String)] {
        var out: [(String, String)] = []
        if let author = pickAuthor() { out.append(("Developer", author)) }
        if let date = formatReleaseDate(viewModel.detail?.datePublished) { out.append(("Released", date)) }
        let genres = pickGenres()
        if !genres.isEmpty { out.append(("Genres", genres.joined(separator: " · "))) }
        if let langs = viewModel.detail?.languages, !langs.isEmpty {
            out.append(("Languages", langs.map { $0.uppercased() }.joined(separator: ", ")))
        }
        return out
    }

    // MARK: Sticky CTA

    private func stickyCta(safeBottom: CGFloat) -> some View {
        // Single full-width gradient strip whose total height = the
        // editorial fade (170pt) + the home-indicator inset, so it
        // covers the entire bottom of the screen including the safe
        // area. `0.45` for the bg0 stop puts the opaque region right
        // above where the button sits — the button + home-indicator
        // zone share the same continuous fade, no panel seam.
        ZStack(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: UGColor.bg0, location: 0.45),
                    .init(color: UGColor.bg0, location: 1.00),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: ctaStripHeight + safeBottom)
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
            // Lift the button above the home-indicator inset so it's
            // never tap-blocked by the system gesture zone.
            .padding(.bottom, safeBottom + 22)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Helpers

    /// Just the year from `datePublished`. JSON-LD allows a full
    /// ISO-8601 timestamp as well as a bare `YYYY` string.
    private func yearFromIso(_ iso: String?) -> String? {
        guard let iso = iso, !iso.isEmpty else { return nil }
        let first4 = iso.prefix(4)
        return first4.count == 4 && first4.allSatisfy { $0.isNumber } ? String(first4) : nil
    }

    /// Pretty `Mon DD, YYYY` from JSON-LD `datePublished`. Drops the
    /// time portion to match what App Store shows. Falls back to
    /// year-only when the date is shorter.
    private func formatReleaseDate(_ iso: String?) -> String? {
        guard let iso = iso, !iso.isEmpty else { return nil }
        if iso.count < 10 { return yearFromIso(iso) }
        let chars = Array(iso)
        guard let y = Int(String(chars[0..<4])),
              let m = Int(String(chars[5..<7])),
              let d = Int(String(chars[8..<10]))
        else { return yearFromIso(iso) }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard m >= 1, m <= 12 else { return yearFromIso(iso) }
        return String(format: "%@ %02d, %d", months[m - 1], d, y)
    }

    /// Prefer JSON-LD `author.name` (sometimes formatted better — e.g.
    /// proper capitalization), fall back to the catalog feed's
    /// `developer.name`. Both fields point at the same studio.
    private func pickAuthor() -> String? {
        if let a = viewModel.detail?.author, !a.isEmpty { return a }
        return viewModel.game.developer.isEmpty ? nil : viewModel.game.developer
    }

    /// JSON-LD `genre[]` is the richer source (multiple values,
    /// includes audience-targeted genres like "For boys"). Catalog
    /// feed's `categoriesNames` is the fallback when JSON-LD didn't
    /// provide one.
    private func pickGenres() -> [String] {
        if let g = viewModel.detail?.genres, !g.isEmpty {
            return g.filter { !$0.isEmpty }
        }
        return viewModel.game.categories.filter { !$0.isEmpty }
    }

    /// Compact rating-count formatter: 12340 → "12.3K",
    /// 1_240_000 → "1.2M", 3000 → "3K" (no trailing ".0").
    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return compact(Double(n) / 1_000_000.0, suffix: "M") }
        if n >= 1_000 { return compact(Double(n) / 1_000.0, suffix: "K") }
        return String(n)
    }

    private func compact(_ v: Double, suffix: String) -> String {
        let rounded = (v * 10).rounded(.down) / 10.0
        if rounded == rounded.rounded(.down), Int(rounded) == Int(rounded.rounded()) {
            return "\(Int(rounded))\(suffix)"
        }
        return String(format: "%.1f%@", rounded, suffix)
    }
}

/// Identifiable wrapper for the screenshot fullscreen sheet's
/// initial-index argument — `.fullScreenCover(item:)` requires
/// Identifiable, and a bare `Int?` won't compile.
struct ScreenshotPager: Identifiable, Equatable {
    let id = UUID()
    let index: Int
}

/// Full-screen pager over the JSON-LD screenshot list. Tap-to-dismiss,
/// horizontal swipe (TabView page style) to flip between shots. Uses
/// `/orig` size — at this point bandwidth is no longer the constraint,
/// image quality is.
struct ScreenshotsFullscreenView: View {
    let screenshots: [String]
    let initialIndex: Int
    let onDismiss: () -> Void

    @State private var page: Int

    init(screenshots: [String], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.screenshots = screenshots
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        _page = State(initialValue: max(0, min(initialIndex, screenshots.count - 1)))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            TabView(selection: $page) {
                ForEach(Array(screenshots.enumerated()), id: \.offset) { idx, url in
                    CachedAsyncImage(url: URL(string: upgradeToOrig(url))) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fit)
                        default:
                            Color.clear
                        }
                    }
                    .tag(idx)
                    .padding(.horizontal, 12)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(UGColor.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 14)
                Spacer()
                if screenshots.count > 1 {
                    Text("\(page + 1) / \(screenshots.count)")
                        .font(UGFont.caption)
                        .foregroundColor(UGColor.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(.bottom, 28)
                }
            }
        }
    }

    /// Replace the `pjpg500x280` (or whatever) suffix with `orig` so
    /// the fullscreen viewer renders the full-quality screenshot.
    /// Mirrors the rewrite logic in CatalogService.rewriteAvatarSize.
    private func upgradeToOrig(_ url: String) -> String {
        guard let lastSlash = url.lastIndex(of: "/"), lastSlash != url.startIndex else { return url }
        return String(url[..<url.index(after: lastSlash)]) + "orig"
    }
}
