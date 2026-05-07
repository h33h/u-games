import SwiftUI

struct ProfileView: View {
    @ObservedObject var service: CatalogService
    let onBack: () -> Void
    let onLoginClick: () -> Void
    let onLogsClick: () -> Void
    let onAboutClick: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            UGColor.bg0.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                UGTopBar(title: "Profile", onBack: onBack)
                Spacer().frame(height: UGSpace.l)
                hero
                    .padding(.horizontal, UGSpace.l)
                Spacer().frame(height: UGSpace.xxxl)
                settingsCard
                    .padding(.horizontal, UGSpace.l)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var hero: some View {
        let p = service.profile
        HStack(alignment: .center, spacing: UGSpace.l) {
            UGAvatar(profile: p, diameter: UGSize.avatarL, plusBorderWidth: 3, fallbackIconSize: 56)
                .contentShape(Circle())
                .onLongPressGesture(minimumDuration: 0.7) {
                    UGHaptics.selection()
                    onLogsClick()
                }
                .accessibilityLabel("Profile picture")
                .accessibilityHint("Long press for diagnostic logs")

            VStack(alignment: .leading, spacing: UGSpace.xs) {
                let displayName = !p.displayName.isEmpty ? p.displayName
                    : (!p.login.isEmpty ? p.login : "Guest")
                Text(displayName)
                    .font(UGFont.titleL)
                    .foregroundColor(UGColor.textPrimary)
                if !p.login.isEmpty && p.login != displayName {
                    Text(p.login)
                        .font(UGFont.bodyS)
                        .foregroundColor(UGColor.textMuted)
                }
                if p.hasYaPlus {
                    UGChip(text: "YANDEX PLUS", style: .accentSoft)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var settingsCard: some View {
        VStack(spacing: 0) {
            if service.profile.isAuthorized {
                SettingsRow(
                    systemIcon: "rectangle.portrait.and.arrow.right",
                    label: "Sign out",
                    danger: true,
                    onTap: onSignOut,
                )
            } else {
                SettingsRow(
                    systemIcon: "person.fill.badge.plus",
                    label: "Sign in",
                    onTap: onLoginClick,
                )
            }
            Divider().background(UGColor.divider)
            SettingsRow(systemIcon: "doc.text", label: "Diagnostic logs", onTap: onLogsClick)
            Divider().background(UGColor.divider)
            SettingsRow(systemIcon: "info.circle", label: "About", onTap: onAboutClick)
        }
        .background(UGColor.elevated)
        .clipShape(RoundedRectangle(cornerRadius: UGRadius.l))
    }
}

private struct SettingsRow: View {
    let systemIcon: String
    let label: String
    var danger: Bool = false
    let onTap: () -> Void

    var body: some View {
        let tint = danger ? UGColor.danger : UGColor.textPrimary
        Button(action: onTap) {
            HStack {
                Image(systemName: systemIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: UGSize.settingsIconCol)
                Text(label)
                    .font(UGFont.bodyS)
                    .foregroundColor(tint)
                Spacer()
                if !danger {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(UGColor.textMuted)
                }
            }
            .padding(.horizontal, UGSpace.l)
            .padding(.vertical, UGSpace.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}
