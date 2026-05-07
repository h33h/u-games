import SwiftUI

struct UGSearchBarShell<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: UGSpace.s) {
            Image(systemName: "magnifyingglass")
                .font(UGFont.bodyS.weight(.semibold))
                .foregroundColor(UGColor.Text.secondary)
            content()
        }
        .padding(.horizontal, UGSpace.l)
        .padding(.vertical, UGSpace.m)
        .background(UGColor.Surface.subtle)
        .overlay(RoundedRectangle(cornerRadius: UGRadius.m).stroke(UGColor.Border.divider))
        .clipShape(RoundedRectangle(cornerRadius: UGRadius.m))
    }
}
