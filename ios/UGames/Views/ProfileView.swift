import SwiftUI

/// Profile tab. Replaces the old `ProfileSheet` modal — full-screen layout
/// with a hero-section (avatar, name, optional Plus pill) and a list of
/// "Settings" rows. Long-press on the avatar still opens diagnostic logs.
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
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(UGColor.textPrimary)
                            .padding(8)
                    }
                    Text("Profile").font(UGFont.titleM).foregroundColor(UGColor.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                Spacer().frame(height: 16)
                hero
                    .padding(.horizontal, 18)
                Spacer().frame(height: 28)
                settingsCard
                    .padding(.horizontal, 18)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var hero: some View {
        let p = service.profile
        HStack(alignment: .center, spacing: 16) {
            Group {
                if p.isAuthorized, let url = URL(string: p.avatarUrl), !p.avatarUrl.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: UGColor.elevated
                        }
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(LinearGradient.ugAccent, lineWidth: p.hasYaPlus ? 3 : 0))
                } else {
                    ZStack {
                        Circle().fill(UGColor.elevated)
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 56))
                            .foregroundColor(UGColor.textMuted)
                    }
                    .frame(width: 96, height: 96)
                }
            }
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: 0.7) { onLogsClick() }

            VStack(alignment: .leading, spacing: 4) {
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
                    Text("YANDEX PLUS")
                        .font(UGFont.caption)
                        .foregroundColor(UGColor.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(UGColor.accent.opacity(0.18))
                        .clipShape(Capsule())
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
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                    .frame(width: 24)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}
