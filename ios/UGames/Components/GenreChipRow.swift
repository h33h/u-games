import SwiftUI

struct GenreChipRow: View {
    let genres: [String]
    let selected: String?
    let onSelect: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: UGSpace.s) {
                chip(label: "All", value: nil)
                ForEach(genres, id: \.self) { g in chip(label: g, value: g) }
            }
            .padding(.horizontal, UGSpace.l)
        }
    }

    private func chip(label: String, value: String?) -> some View {
        let active = (value == selected) || (value == nil && selected == nil)
        return Text(label)
            .font(UGFont.bodyS)
            .foregroundColor(active ? UGColor.bg0 : UGColor.textSecondary)
            .padding(.horizontal, UGSpace.l).padding(.vertical, UGSpace.s)
            .background(active ? UGColor.accent : UGColor.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(active ? UGColor.accent : UGColor.divider))
            .ugShadow(.glow(active ? UGColor.accent : nil))
            .padding(.vertical, UGSpace.m)
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
