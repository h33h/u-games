import SwiftUI

struct StoryCard: View {
    let title: String
    let subtitle: String
    let games: [Game]
    let onTap: () -> Void

    private var anchor: Color { Color(hex: games.first?.mainColor) ?? UGColor.Accent.primary }

    var body: some View {
        Button {
            UGHaptics.tap()
            onTap()
        } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [anchor.opacity(0.55), Color(red: 0x0A/255.0, green: 0x04/255.0, blue: 0x18/255.0)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                stackedCovers
                LinearGradient(
                    stops: [.init(color: .clear, location: 0.5), .init(color: .black.opacity(0.6), location: 1.0)],
                    startPoint: .top, endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: UGSpace.xs) {
                    Text(subtitle)
                        .font(UGFont.label)
                        .foregroundColor(UGColor.Text.secondary)
                    Text(title)
                        .font(UGFont.titleL)
                        .foregroundColor(UGColor.Text.primary)
                        .lineLimit(2)
                }
                .padding(UGSpace.l)
            }
            .frame(height: UGSize.storyH)
            .haloChrome(anchor, size: .xl)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(subtitle). \(title)")
    }

    private var stackedCovers: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(Array(games.prefix(3).enumerated()), id: \.element.appId) { idx, g in
                let placeholder = Color(hex: g.mainColor) ?? UGColor.Surface.raised
                CachedAsyncImage(url: URL(string: g.iconUrl.isEmpty ? g.coverUrl : g.iconUrl)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
                .frame(width: UGSize.storyMiniCover, height: UGSize.storyMiniCover)
                .clipShape(RoundedRectangle(cornerRadius: UGRadius.s))
                .clipped()
                .rotationEffect(.degrees(Double(-8 + idx * 8)))
                .offset(x: CGFloat(-14 - idx * 8), y: 24)
                .ugShadow(.elevation(.stacked))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

@available(iOS 17.0, *)
#Preview(traits: .fixedLayout(width: 360, height: 200)) {
    ZStack {
        Color.black.ignoresSafeArea()
        StoryCard(
            title: "5 brain-bending puzzles to try this week",
            subtitle: "SPOTLIGHT · ISSUE #04",
            games: [
                Game(appId: 1, title: "A", rating: 0, ratingCount: 0, coverUrl: "", iconUrl: "", categories: [], developer: "", mainColor: "#9B6CFF"),
                Game(appId: 2, title: "B", rating: 0, ratingCount: 0, coverUrl: "", iconUrl: "", categories: [], developer: "", mainColor: "#43E890"),
                Game(appId: 3, title: "C", rating: 0, ratingCount: 0, coverUrl: "", iconUrl: "", categories: [], developer: "", mainColor: "#FF7EB9"),
            ],
            onTap: {}
        )
        .padding(14)
    }
}
