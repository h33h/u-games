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

    /// Parse the body of an `orient` log message. The `orient` channel
    /// carries two kinds of payload:
    ///   1. Real orientation signals — `screen.orientation.lock()` targets
    ///      ("landscape", "landscape-primary", "portrait", …) and
    ///      canvas-aspect-inferred reports ("landscape (canvas 1920x1080 …)").
    ///      All of these *start* with "landscape" or "portrait".
    ///   2. Diagnostic viewport dumps from `reportViewport()` — strings like
    ///      "atstart inner=375x812 …" or "boot+2s inner=…" that may also
    ///      embed the words "landscape"/"portrait" inside the meta viewport
    ///      content, but always *start* with a stage name.
    /// We must only react to (1). A loose `contains` match used to let (2)
    /// flip `required` to the wrong value mid-session, producing a flashing
    /// overlay aimed at the wrong orientation.
    func setFromString(_ s: String) {
        let lower = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.hasPrefix("landscape") {
            required = .landscape
        } else if lower.hasPrefix("portrait") {
            required = .portrait
        }
    }
}
