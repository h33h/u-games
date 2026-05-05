import SwiftUI

struct GenreChipRow: View {
    let genres: [String]
    let selected: String?
    let onSelect: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "All", value: nil)
                ForEach(genres, id: \.self) { g in chip(label: g, value: g) }
            }
            .padding(.horizontal, 14)
        }
    }

    private func chip(label: String, value: String?) -> some View {
        let active = (value == selected) || (value == nil && selected == nil)
        return Text(label)
            .font(UGFont.bodyS)
            .foregroundColor(active ? UGColor.bg0 : UGColor.textSecondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(active ? UGColor.accent : UGColor.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(active ? UGColor.accent : UGColor.divider))
            .shadow(color: active ? UGColor.accent.opacity(0.4) : .clear, radius: 8, x: 0, y: 0)
            .onTapGesture { onSelect(value) }
    }
}

@available(iOS 17.0, *)
#Preview(traits: .fixedLayout(width: 400, height: 60)) {
    ZStack {
        Color.black.ignoresSafeArea()
        GenreChipRow(
            genres: ["Action", "Puzzle", "Racing", "Casual", "Word"],
            selected: "Puzzle",
            onSelect: { _ in }
        )
    }
}
