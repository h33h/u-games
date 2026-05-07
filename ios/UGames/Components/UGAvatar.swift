import SwiftUI

/// Circular user avatar with two states: signed-in (remote image +
/// optional Yandex Plus accent ring) and signed-out (system silhouette
/// on `elevated`). Used in the Home greeting and the Profile screen
/// hero — same model, two diameters.
struct UGAvatar: View {
    let profile: UserProfile
    var diameter: CGFloat = UGSize.avatarS
    /// Accent ring stroke width when the user has Yandex Plus.
    var plusBorderWidth: CGFloat = 2
    /// Glyph size used for the signed-out fallback.
    var fallbackIconSize: CGFloat = 22

    var body: some View {
        Group {
            if profile.isAuthorized,
               let url = URL(string: profile.avatarUrl),
               !profile.avatarUrl.isEmpty {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        UGColor.elevated
                    }
                }
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(
                        LinearGradient.ugAccent,
                        lineWidth: profile.hasYaPlus ? plusBorderWidth : 0
                    )
                )
            } else {
                ZStack {
                    Circle().fill(UGColor.elevated)
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: fallbackIconSize))
                        .foregroundColor(UGColor.textSecondary)
                }
                .frame(width: diameter, height: diameter)
            }
        }
    }
}
