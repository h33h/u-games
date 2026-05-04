import Foundation
import SwiftUI

/// Tracks the orientation a running game has requested via
/// `screen.orientation.lock()`. The SDK stub traps that call inside the
/// game iframe and forwards the requested target to native via the
/// `ugamesLog` message handler with tag `"orient"`. GameView observes
/// this store to decide whether to show the "rotate device" overlay.
@MainActor
final class OrientationStore: ObservableObject {
    static let shared = OrientationStore()

    enum Required { case landscape, portrait }

    @Published var required: Required? = nil

    private init() {}

    /// Reset before opening a new game. The next iframe load will re-trigger
    /// `screen.orientation.lock()` if the new game has a preference.
    func reset() { required = nil }

    /// Parse the body of an `orient` log message. Yandex SDK calls usually
    /// pass strings like "landscape", "landscape-primary", or "portrait".
    func setFromString(_ s: String) {
        let lower = s.lowercased()
        if lower.contains("landscape") {
            required = .landscape
        } else if lower.contains("portrait") {
            required = .portrait
        }
    }
}
