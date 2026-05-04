import Foundation
import SwiftUI

/// Diagnostic log buffer. In-memory ring of the last `maxEntries` events
/// emitted by the inject scripts (via `webkit.messageHandlers.ugamesLog`)
/// and by native code (auth watcher, profile fetch, cookie state). Use
/// LogsView to inspect at runtime; long-press the profile button on the
/// catalog topbar to open it.
struct LogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let tag: String
    let message: String
}

@MainActor
final class LogStore: ObservableObject {
    static let shared = LogStore()

    @Published private(set) var entries: [LogEntry] = []
    private let maxEntries = 500

    private init() {}

    func log(_ tag: String, _ message: String) {
        entries.append(LogEntry(timestamp: Date(), tag: tag, message: message))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        NSLog("[ugames/\(tag)] \(message)")
    }

    func clear() { entries.removeAll() }

    func dump() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return entries.map { "\(f.string(from: $0.timestamp)) [\($0.tag)] \($0.message)" }
            .joined(separator: "\n")
    }
}

/// Thread-safe entry point for non-MainActor callers (URLSession completion
/// blocks, WKScriptMessageHandler closures, watcher tasks).
enum Log {
    static func write(_ tag: String, _ message: String) {
        Task { @MainActor in LogStore.shared.log(tag, message) }
    }
}
