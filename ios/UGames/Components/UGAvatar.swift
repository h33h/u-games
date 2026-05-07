import SwiftUI

struct UGAvatar: View {
    let profile: UserProfile
    var diameter: CGFloat = UGSize.avatarS

    var plusBorderWidth: CGFloat = 2

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
                        UGColor.Surface.raised
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
                    Circle().fill(UGColor.Surface.raised)
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: fallbackIconSize))
                        .foregroundColor(UGColor.Text.secondary)
                }
                .frame(width: diameter, height: diameter)
            }
        }
    }
}
