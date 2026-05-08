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
    @State private var exiting: Bool = false
    @State private var orientationProbed: Bool = false
    // Latches once the WebView mounts so a later rotation can't tear it down.
    @State private var webViewSpawned: Bool = false
    @StateObject private var orient: OrientationStore = .shared

    var body: some View {
        GeometryReader { proxy in
            let isPortrait = proxy.size.height >= proxy.size.width
            content(isPortrait: isPortrait)
        }
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .bottom)
    }

    @ViewBuilder
    private func content(isPortrait: Bool) -> some View {
        let mismatch = orientationMismatch(isPortrait: isPortrait)
        let allowMount = webViewSpawned || (orientationProbed && !mismatch)
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if allowMount, let url = URL(string: "https://yandex.com/games/app/\(appId)") {
                GameWebView(
                    url: url,
                    scripts: scripts,
                    blockList: blockList,
                    paused: mismatch,
                )
                .ignoresSafeArea()
                .onAppear { webViewSpawned = true }
            }

            Color.clear
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
                .onTapGesture { revision += 1 }
                .accessibilityHidden(true)

            if showBack {
                UGCircleIconButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Back to catalog",
                    tint: .white,
                    diameter: 40,
                    iconSize: 18,
                    background: Color.black.opacity(0.8),
                    action: handleBack
                )
                .padding(.leading, UGSpace.m)
                .padding(.top, UGSpace.s)
                .transition(.opacity)
            }

            if mismatch, let target = orient.required {
                RotateDeviceOverlay(target: target, onBack: handleBack)
                    .ignoresSafeArea()
                    .transition(.opacity)
            } else if !orientationProbed && !webViewSpawned {
                LoadingOverlay()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            if exiting {
                Color.black
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: revision) { _ in scheduleHide() }
        .onAppear {
            orient.reset()
            orient.gameActive = true
            scheduleHide()
            probeOrientation()
        }
        .onDisappear {
            orient.reset()
            orient.gameActive = false
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width > 80 && abs(value.translation.height) < 60 {
                        handleBack()
                    }
                }
        )
    }

    private func handleBack() {
        guard !exiting else { return }
        exiting = true
        orient.gameActive = false
        requestPortrait()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            onBack()
        }
    }

    private func orientationMismatch(isPortrait: Bool) -> Bool {
        switch orient.required {
        case .landscape: return isPortrait
        case .portrait: return !isPortrait
        case .none: return false
        }
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

    // Fetch the play page and read `gameSettings.features.orientation` from
    // __playPageData__, mirroring Yandex's own gameOrientation getter.
    private func probeOrientation() {
        guard !orientationProbed else { return }
        guard let url = URL(string: "https://yandex.com/games/app/\(appId)") else {
            orientationProbed = true
            return
        }
        Task {
            await Self.fetchOrientationHint(url: url)
            await MainActor.run { orientationProbed = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if !orientationProbed {
                Log.write("orient", "probe timeout")
                orientationProbed = true
            }
        }
    }

    private static func fetchOrientationHint(url: URL) async {
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let html = String(data: data, encoding: .utf8)
            else { return }
            if let hint = parseOrientationHint(html) {
                Log.write("orient", "probe hint: \(hint) (playPageData)")
                await MainActor.run { OrientationStore.shared.setFromString(hint) }
            } else {
                Log.write("orient", "probe: no requirement (rotatable)")
            }
        } catch {
            Log.write("orient", "probe error: \((error as NSError).localizedDescription)")
        }
    }

    private static func parseOrientationHint(_ html: String) -> String? {
        guard let payload = extractPlayPageDataJSON(html),
              let data = payload.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        func featureOrientation(_ key: String) -> String? {
            guard let parent = root[key] as? [String: Any],
                  let features = parent["features"] as? [String: Any],
                  let value = features["orientation"] as? String
            else { return nil }
            return value.lowercased()
        }
        for raw in [featureOrientation("gameSettings"), featureOrientation("gameData")] {
            guard let v = raw else { continue }
            if v == "landscape" || v == "portrait" { return v }
        }
        return nil
    }

    // Yandex SSR ships __playPageData__ as the body of an inert
    // `<script id="__playPageData__" type="mime/invalid">{...JSON...}</script>`.
    private static func extractPlayPageDataJSON(_ html: String) -> String? {
        let needles = ["id=\"__playPageData__\"", "id='__playPageData__'"]
        guard let attr = needles.lazy.compactMap({ html.range(of: $0) }).first,
              html.range(of: "<script", options: .backwards, range: html.startIndex..<attr.upperBound) != nil,
              let tagClose = html.range(of: ">", range: attr.upperBound..<html.endIndex),
              let bodyEnd = html.range(of: "</script>", range: tagClose.upperBound..<html.endIndex)
        else { return nil }
        return String(html[tagClose.upperBound..<bodyEnd.lowerBound])
    }

    private func requestPortrait() {
        guard let scene = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

private struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.4)
        }
    }
}

private struct RotateDeviceOverlay: View {
    let target: OrientationStore.Required
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            VStack(spacing: UGSpace.xxxl) {
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
                    .padding(.horizontal, UGSpace.huge)

                Button {
                    UGHaptics.tap()
                    onBack()
                } label: {
                    Text("Back to catalog")
                        .font(.callout)
                        .foregroundColor(.white)
                        .padding(.horizontal, UGSpace.xxl)
                        .padding(.vertical, UGSpace.m)
                        .overlay(
                            RoundedRectangle(cornerRadius: UGRadius.xl)
                                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        )
                }
                .padding(.top, UGSpace.s)
            }
            .padding()
        }
    }

    private var headline: String {
        target == .landscape ? "Rotate your device" : "Rotate to portrait"
    }
    private var subheadline: String {
        target == .landscape
            ? "This game runs in landscape."
            : "This game runs in portrait."
    }
}
