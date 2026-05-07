import SwiftUI

struct GameDetailView: View {
    @ObservedObject var viewModel: GameDetailViewModel
    @ObservedObject var favorites: FavoritesStore
    let onBack: () -> Void
    let onPlay: (Game) -> Void
    let onShare: (Game) -> Void
    let onSimilarClick: (Game) -> Void

    @State private var ctaScale: CGFloat = 1.0

    @State private var fullscreen: ScreenshotPager?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let ctaStripHeight: CGFloat = 120

    private var halo: Color { Color(hex: viewModel.game.mainColor) ?? UGColor.Accent.primary }
    private var placeholder: Color { Color(hex: viewModel.game.mainColor) ?? UGColor.Surface.raised }

    var body: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom
            ZStack(alignment: .bottom) {
                UGColor.Surface.base
                ScrollView {
                    LazyVStack(spacing: 0) {
                        hero
                        Spacer().frame(height: UGSpace.xl)
                        titleBlock
                        Spacer().frame(height: UGSpace.xxl)
                        aboutSection
                        screenshotsRow
                        Spacer().frame(height: UGSpace.xxl)
                        SectionHeader(title: "More like this")
                        Spacer().frame(height: UGSpace.m)
                        similarRow
                        Spacer().frame(height: UGSpace.xxl)
                        informationBlock

                        Spacer().frame(height: ctaStripHeight + safeBottom)
                    }
                }
                .ignoresSafeArea(edges: .top)
                stickyCta(safeBottom: safeBottom)

                heroTopRow
                    .padding(.top, max(safeTop, 44) + UGSpace.s)
                    .padding(.horizontal, UGSpace.l)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 1.4).repeatCount(1, autoreverses: true)) {
                    ctaScale = 1.04
                }
            }
        }
        .fullScreenCover(item: $fullscreen) { pager in
            ScreenshotsFullscreenView(
                screenshots: viewModel.detail?.screenshots ?? [],
                initialIndex: pager.index,
                onDismiss: { fullscreen = nil },
                onPlay: {
                    fullscreen = nil
                    onPlay(viewModel.game)
                }
            )
        }
    }

    private var hero: some View {
        ZStack(alignment: .top) {
            stretchyCover
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.30),
                    .init(color: UGColor.Surface.base, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .frame(height: UGSize.heroDetailH)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(halo.opacity(UGShadow.HaloSize.xl.borderAlpha))
                .frame(height: 0.5)
        }
        .ugShadow(.halo(.xl, halo))
    }

    private var stretchyCover: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .global).minY
            let stretch = max(0, minY)
            CoverImage(
                url: URL(string: viewModel.game.coverUrl(size: "pjpg1280x720")),
                placeholder: placeholder
            )
            .frame(width: geo.size.width, height: geo.size.height + stretch)
            .clipped()
            .offset(y: -stretch)
        }
    }

    private var heroTopRow: some View {
        let isFav = favorites.contains(viewModel.game.appId)
        return HStack {
            UGCircleIconButton(
                systemName: "chevron.left",
                accessibilityLabel: "Back",
                action: onBack
            )
            Spacer()
            UGCircleIconButton(
                systemName: isFav ? "heart.fill" : "heart",
                accessibilityLabel: isFav ? "Remove from favorites" : "Add to favorites",
                tint: isFav ? UGColor.Feedback.danger : UGColor.Text.primary,
                action: { favorites.toggle(viewModel.game) }
            )
            UGCircleIconButton(
                systemName: "square.and.arrow.up",
                accessibilityLabel: "Share game",
                action: { onShare(viewModel.game) }
            )
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: UGSpace.m) {
            let eyebrow = [
                viewModel.game.categories.first?.uppercased(),
                yearFromIso(viewModel.detail?.datePublished),
            ].compactMap { $0 }.joined(separator: " · ")
            if !eyebrow.isEmpty {
                UGEyebrow(text: eyebrow)
            }
            Text(viewModel.game.title)
                .font(UGFont.displayXL)
                .foregroundColor(UGColor.Text.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let author = pickAuthor() {
                Text("by \(author)")
                    .font(UGFont.bodyS)
                    .foregroundColor(UGColor.Text.secondary)
                    .lineLimit(1)
            }
            chipsRow
        }
        .padding(.horizontal, UGSpace.l)
    }

    @ViewBuilder
    private var chipsRow: some View {
        let chips = buildChips()
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: UGSpace.s) {
                    ForEach(chips, id: \.self) { c in
                        UGChip(text: c, style: .neutral)
                    }
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

    @ViewBuilder
    private var aboutSection: some View {
        let description = viewModel.detail?.description
        if let text = description, !text.isEmpty {
            VStack(alignment: .leading, spacing: UGSpace.s) {
                UGEyebrow(text: "About")
                Text(text)
                    .font(UGFont.body)
                    .foregroundColor(UGColor.Text.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, UGSpace.l)
            .padding(.bottom, UGSpace.xl)
        } else if viewModel.isLoadingDetail {
            VStack(alignment: .leading, spacing: UGSpace.s) {
                UGEyebrow(text: "About")
                ForEach(0..<3) { _ in
                    Skeleton(cornerRadius: UGSpace.xs).frame(height: UGSpace.m)
                }
            }
            .padding(.horizontal, UGSpace.l)
            .padding(.bottom, UGSpace.xl)
        }
    }

    @ViewBuilder
    private var screenshotsRow: some View {
        let urls = viewModel.detail?.screenshots ?? []
        if !urls.isEmpty {
            VStack(alignment: .leading, spacing: UGSpace.s) {
                UGEyebrow(text: "Screenshots")
                    .padding(.horizontal, UGSpace.l)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: UGSpace.s) {
                        ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                            screenshotTile(url: url)
                                .onTapGesture { fullscreen = ScreenshotPager(index: idx) }
                        }
                    }
                    .padding(.horizontal, UGSpace.l)
                }
            }
        } else if viewModel.isLoadingDetail {
            VStack(alignment: .leading, spacing: UGSpace.s) {
                UGEyebrow(text: "Screenshots")
                    .padding(.horizontal, UGSpace.l)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: UGSpace.s) {
                        ForEach(0..<3) { _ in
                            Skeleton(cornerRadius: UGRadius.l)
                                .frame(width: UGSize.screenshotW, height: UGSize.screenshotH)
                        }
                    }
                    .padding(.horizontal, UGSpace.l)
                }
            }
        }
    }

    private func screenshotTile(url: String) -> some View {
        CoverImage(url: URL(string: url))
            .frame(width: UGSize.screenshotW, height: UGSize.screenshotH)
            .haloChrome(halo, size: .sm)
    }

    @ViewBuilder
    private var similarRow: some View {
        if viewModel.isLoadingSimilar {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: UGSpace.m) {
                    ForEach(0..<3) { _ in
                        Skeleton(cornerRadius: UGRadius.l)
                            .frame(width: UGSize.similarTileW, height: UGSize.similarTileH)
                    }
                }
                .padding(.horizontal, UGSpace.l)
            }
        } else if viewModel.similar.isEmpty {
            if viewModel.similarError != nil {
                Text("Couldn't load related games")
                    .font(UGFont.bodyS)
                    .foregroundColor(UGColor.Text.muted)
                    .padding(.horizontal, UGSpace.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                EmptyView()
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: UGSpace.m) {
                    ForEach(viewModel.similar, id: \.appId) { g in
                        GameCard(
                            game: g,
                            style: .tile,
                            isFavorite: favorites.contains(g.appId),
                            onTap: { onSimilarClick(g) },
                            onFavoriteToggle: { favorites.toggle(g) }
                        )
                        .frame(width: UGSize.similarTileW)
                    }
                }
                .padding(.horizontal, UGSpace.l)
            }
        }
    }

    @ViewBuilder
    private var informationBlock: some View {
        let rows = buildInfoRows()
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: UGSpace.s) {
                UGEyebrow(text: "Information")
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                        if idx > 0 {
                            Divider().background(UGColor.Border.divider)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: UGSpace.s) {
                            Text(row.label)
                                .font(UGFont.bodyS)
                                .foregroundColor(UGColor.Text.muted)
                                .frame(minWidth: UGSize.infoLabelCol, alignment: .leading)
                                .fixedSize(horizontal: true, vertical: false)
                            Text(row.value)
                                .font(UGFont.bodyS)
                                .foregroundColor(UGColor.Text.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, UGSpace.l)
                        .padding(.vertical, UGSpace.l)
                    }
                }
                .background(UGColor.Surface.raised)
                .clipShape(RoundedRectangle(cornerRadius: UGRadius.l))
            }
            .padding(.horizontal, UGSpace.l)
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

    private func stickyCta(safeBottom: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: UGColor.Surface.base, location: 0.35),
                    .init(color: UGColor.Surface.base, location: 1.00),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: ctaStripHeight + safeBottom)
            .allowsHitTesting(false)
            UGPillButton(title: "▶ Play now", size: .large, glow: true) {
                onPlay(viewModel.game)
            }
            .scaleEffect(ctaScale)
            .padding(.bottom, safeBottom + UGSpace.l)
        }
        .frame(maxWidth: .infinity)
    }

    private func yearFromIso(_ iso: String?) -> String? {
        guard let iso = iso, !iso.isEmpty else { return nil }
        let first4 = iso.prefix(4)
        return first4.count == 4 && first4.allSatisfy { $0.isNumber } ? String(first4) : nil
    }

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

    private func pickAuthor() -> String? {
        if let a = viewModel.detail?.author, !a.isEmpty { return a }
        return viewModel.game.developer.isEmpty ? nil : viewModel.game.developer
    }

    private func pickGenres() -> [String] {
        if let g = viewModel.detail?.genres, !g.isEmpty {
            return g.filter { !$0.isEmpty }
        }
        return viewModel.game.categories.filter { !$0.isEmpty }
    }

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

struct ScreenshotPager: Identifiable, Equatable {
    let id = UUID()
    let index: Int
}

struct ScreenshotsFullscreenView: View {
    let screenshots: [String]
    let initialIndex: Int
    let onDismiss: () -> Void
    let onPlay: () -> Void

    @State private var page: Int
    @State private var anyZoomed: Bool = false

    init(
        screenshots: [String],
        initialIndex: Int,
        onDismiss: @escaping () -> Void,
        onPlay: @escaping () -> Void
    ) {
        self.screenshots = screenshots
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        self.onPlay = onPlay
        _page = State(initialValue: max(0, min(initialIndex, screenshots.count - 1)))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
                .onTapGesture { if !anyZoomed { onDismiss() } }
            TabView(selection: $page) {
                ForEach(Array(screenshots.enumerated()), id: \.offset) { idx, url in
                    ZoomableImage(
                        url: URL(string: upgradeToOrig(url)),
                        isZoomed: Binding(
                            get: { anyZoomed && page == idx },
                            set: { newValue in
                                if page == idx { anyZoomed = newValue }
                            }
                        )
                    )
                    .tag(idx)
                    .padding(.horizontal, UGSpace.m)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: page) { _ in anyZoomed = false }

            VStack {
                HStack {
                    Spacer()
                    UGCircleIconButton(
                        systemName: "xmark",
                        accessibilityLabel: "Close screenshots",
                        action: onDismiss
                    )
                }
                .padding(.horizontal, UGSpace.l)
                Spacer()
                UGPillButton(title: "▶ Play now", glow: true, action: onPlay)
                    .padding(.bottom, UGSpace.m)
                if screenshots.count > 1 {
                    UGChip(text: "\(page + 1) / \(screenshots.count)", style: .overlay)
                        .padding(.bottom, UGSpace.xxl)
                }
            }
            .opacity(anyZoomed ? 0.0 : 1.0)
            .animation(.easeOut(duration: 0.18), value: anyZoomed)
        }
    }

    private func upgradeToOrig(_ url: String) -> String {
        guard let lastSlash = url.lastIndex(of: "/"), lastSlash != url.startIndex else { return url }
        return String(url[..<url.index(after: lastSlash)]) + "orig"
    }
}

private struct ZoomableImage: View {
    let url: URL?
    @Binding var isZoomed: Bool

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            CachedAsyncImage(url: url) { phase in
                Group {
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fit)
                    default:
                        Color.clear
                    }
                }
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: geo.size.width, height: geo.size.height)
                .gesture(magnification)
                .simultaneousGesture(panWhenZoomed, including: isZoomed ? .all : .none)
                .onTapGesture(count: 2) { toggleDoubleTapZoom() }
            }
        }
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { val in
                let newScale = max(1.0, min(5.0, lastScale * val))
                scale = newScale
                isZoomed = newScale > 1.05
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.05 { resetTransform() }
            }
    }

    private var panWhenZoomed: some Gesture {
        DragGesture()
            .onChanged { val in
                guard scale > 1.05 else { return }
                offset = CGSize(
                    width: lastOffset.width + val.translation.width,
                    height: lastOffset.height + val.translation.height
                )
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func toggleDoubleTapZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if scale > 1.0 {
                resetTransform()
            } else {
                scale = 2.5
                lastScale = 2.5
                isZoomed = true
            }
        }
    }

    private func resetTransform() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
        isZoomed = false
    }
}
