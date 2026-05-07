import Foundation
import SwiftUI

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

enum Log {
    static func write(_ tag: String, _ message: String) {
        Task { @MainActor in LogStore.shared.log(tag, message) }
    }
}
