import SwiftUI
import UIKit

struct GameView: View {
    let appId: Int64
    let title: String
    let scripts: InjectedScripts
    let blockList: BlockList
    let onBack: () -> Void

    @State private var showBack: Bool = true
    @State private var revision: Int = 0
    @StateObject private var orient: OrientationStore = .shared
    @State private var deviceIsPortrait: Bool = !UIDevice.current.orientation.isLandscape

    private var rotateOverlayVisible: Bool {
        switch orient.required {
        case .landscape: return deviceIsPortrait
        case .portrait: return !deviceIsPortrait
        case .none: return false
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let url = URL(string: "https://yandex.com/games/app/\(appId)") {
                GameWebView(url: url, scripts: scripts, blockList: blockList)
            }

            // Tap-to-reveal hot zone — small enough to not steal touches.
            Color.clear
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
                .onTapGesture { revision += 1 }

            if showBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.8))
                        .clipShape(Circle())
                }
                .padding(.leading, 12)
                .padding(.top, 8)
                .transition(.opacity)
            }

            if rotateOverlayVisible {
                RotateDeviceOverlay(target: orient.required ?? .landscape, onBack: onBack)
                    .transition(.opacity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: revision) { _ in scheduleHide() }
        .onAppear {
            orient.reset()
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            updateDeviceOrientation()
            scheduleHide()
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            orient.reset()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateDeviceOrientation()
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width > 80 && abs(value.translation.height) < 60 {
                        onBack()
                    }
                }
        )
    }

    private func updateDeviceOrientation() {
        let o = UIDevice.current.orientation
        if o.isLandscape {
            withAnimation { deviceIsPortrait = false }
        } else if o.isPortrait {
            withAnimation { deviceIsPortrait = true }
        }
        // Unknown / face-up / face-down: keep previous value.
    }

    private func scheduleHide() {
        showBack = true
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation { showBack = false }
            }
        }
    }
}

/// Full-screen overlay shown when the running game requested an orientation
/// that the device is not currently in. Rotation is detected via
/// `screen.orientation.lock()` calls trapped by the SDK stub.
private struct RotateDeviceOverlay: View {
    let target: OrientationStore.Required
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 28) {
                Image(systemName: "rotate.right")
                    .font(.system(size: 96, weight: .light))
                    .foregroundColor(.white)
                    .rotationEffect(target == .landscape ? .degrees(0) : .degrees(90))

                Text(headline)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(subheadline)
                    .font(.callout)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: onBack) {
                    Text("Назад в каталог")
                        .font(.callout)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        )
                }
                .padding(.top, 8)
            }
            .padding()
        }
    }

    private var headline: String {
        target == .landscape ? "Поверните устройство" : "Поверните в портрет"
    }
    private var subheadline: String {
        target == .landscape
            ? "Эта игра работает в горизонтальной ориентации."
            : "Эта игра работает в вертикальной ориентации."
    }
}
