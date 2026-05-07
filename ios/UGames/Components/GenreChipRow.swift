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
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: 0.04),
                    .init(color: .black, location: 0.96),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .leading, endPoint: .trailing
            )
        )
    }

    private func chip(label: String, value: String?) -> some View {
        let active = (value == selected) || (value == nil && selected == nil)
        return Text(label)
            .font(UGFont.bodyS)
            .foregroundColor(active ? UGColor.Surface.base : UGColor.Text.secondary)
            .padding(.horizontal, UGSpace.l).padding(.vertical, UGSpace.s)
            .background(active ? UGColor.Accent.primary : UGColor.Surface.subtle)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(active ? UGColor.Accent.primary : UGColor.Border.divider))
            .ugShadow(.glow(.subtle, active ? UGColor.Accent.primary : .clear))
            .padding(.vertical, UGSpace.m)
            .onTapGesture {
                UGHaptics.selection()
                onSelect(value)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(active ? .isSelected : [])
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
