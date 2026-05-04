import SwiftUI
import UIKit

struct LogsView: View {
    @ObservedObject var store: LogStore = .shared
    let onClose: () -> Void

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                if store.entries.isEmpty {
                    Text("No log entries yet.\nReproduce the issue, then re-open this view.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(store.entries) { e in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text(timeFormatter.string(from: e.timestamp))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.gray)
                                        Text(e.tag)
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundColor(colorFor(tag: e.tag))
                                        Text(e.message)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.white)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .id(e.id)
                                    .padding(.horizontal, 12)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .onAppear {
                            if let last = store.entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                        .onChange(of: store.entries.count) { _ in
                            if let last = store.entries.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { onClose() }.foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button("Copy") {
                            UIPasteboard.general.string = store.dump()
                        }.foregroundColor(.white)
                        Button("Clear") { store.clear() }.foregroundColor(Color(.systemRed))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func colorFor(tag: String) -> Color {
        switch tag {
        case "auth": return Color(.systemTeal)
        case "profile": return Color(.systemGreen)
        case "drawer": return Color(.systemYellow)
        case "sdk": return Color(.systemOrange)
        case "nav": return Color(.systemPurple)
        case "cookie": return Color(.systemBlue)
        default: return Color(.systemPink)
        }
    }
}
