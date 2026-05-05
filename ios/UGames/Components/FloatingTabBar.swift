import SwiftUI

struct UGTab: Identifiable, Equatable {
    let key: String
    let label: String
    let systemIcon: String
    var id: String { key }
}

struct FloatingTabBar: View {
    let tabs: [UGTab]
    let selectedKey: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                let active = tab.key == selectedKey
                VStack(spacing: 2) {
                    Image(systemName: tab.systemIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(active ? UGColor.accent : UGColor.textMuted)
                    Text(tab.label)
                        .font(UGFont.caption)
                        .foregroundColor(active ? UGColor.accent : UGColor.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture { onSelect(tab.key) }
            }
        }
        .frame(height: 62)
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial)
        .background(UGColor.surface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(UGColor.divider))
        .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 12)
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }
}

@available(iOS 17.0, *)
#Preview(traits: .fixedLayout(width: 400, height: 110)) {
    ZStack {
        Color.black.ignoresSafeArea()
        FloatingTabBar(
            tabs: [
                .init(key: "home", label: "Home", systemIcon: "house.fill"),
                .init(key: "browse", label: "Browse", systemIcon: "square.grid.2x2.fill"),
                .init(key: "favorites", label: "Favorites", systemIcon: "heart.fill"),
                .init(key: "profile", label: "Profile", systemIcon: "person.crop.circle.fill"),
            ],
            selectedKey: "home",
            onSelect: { _ in }
        )
    }
}
