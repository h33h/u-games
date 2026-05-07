import SwiftUI

struct StoryCard: View {
    let title: String
    let subtitle: String
    let games: [Game]
    let onTap: () -> Void

    private var anchor: Color { Color(hex: games.first?.mainColor) ?? UGColor.accent }

    var body: some View {
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
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(UGFont.label)
                    .foregroundColor(UGColor.textSecondary)
                Text(title)
                    .font(UGFont.titleL)
                    .foregroundColor(UGColor.textPrimary)
                    .lineLimit(2)
            }
            .padding(18)
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(anchor.opacity(UGColor.haloBorderAlpha)))
        .shadow(color: anchor.opacity(UGColor.haloAlpha), radius: 20, x: 0, y: 14)
        .onTapGesture(perform: onTap)
    }

    private var stackedCovers: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(Array(games.prefix(3).enumerated()), id: \.element.appId) { idx, g in
                let placeholder = Color(hex: g.mainColor) ?? UGColor.elevated
                CachedAsyncImage(url: URL(string: g.iconUrl.isEmpty ? g.coverUrl : g.iconUrl)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .clipped()
                .rotationEffect(.degrees(Double(-8 + idx * 8)))
                .offset(x: CGFloat(-14 - idx * 8), y: 24)
                .shadow(radius: 6)
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
