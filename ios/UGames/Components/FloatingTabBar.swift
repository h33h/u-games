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
                VStack(spacing: UGSpace.xs) {
                    Image(systemName: tab.systemIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(active ? UGColor.accent : UGColor.textMuted)
                    Text(tab.label)
                        .font(UGFont.caption)
                        .foregroundColor(active ? UGColor.accent : UGColor.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, UGSpace.s)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !active {
                        UGHaptics.selection()
                        onSelect(tab.key)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .frame(height: UGSize.tabBarH)
        .padding(.horizontal, UGSpace.xs)
        .background(.ultraThinMaterial)
        .background(UGColor.surface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: UGRadius.xxl))
        .overlay(RoundedRectangle(cornerRadius: UGRadius.xxl).stroke(UGColor.divider))
        .ugShadow(.chrome)
        .padding(.horizontal, UGSpace.xxl)
        .padding(.bottom, UGSpace.l)
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
