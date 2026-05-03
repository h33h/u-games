import SwiftUI

struct CatalogView: View {
    @ObservedObject var service: CatalogService
    let onGameClick: (Game) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if service.games.isEmpty && service.isLoading {
                ProgressView().tint(.white)
            } else if service.games.isEmpty, let err = service.error {
                VStack(spacing: 16) {
                    Text(err).foregroundColor(.white).multilineTextAlignment(.center)
                    Button("Retry") { Task { await service.reload() } }
                        .buttonStyle(.borderedProminent)
                }.padding(24)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(service.games) { game in
                            GameCard(game: game)
                                .onTapGesture { onGameClick(game) }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .task { await service.loadInitial() }
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
