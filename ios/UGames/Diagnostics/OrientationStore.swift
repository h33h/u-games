import Foundation
import SwiftUI

@MainActor
final class OrientationStore: ObservableObject {
    static let shared = OrientationStore()

    enum Required { case landscape, portrait }

    @Published var required: Required? = nil

    private init() {}

    func reset() { required = nil }

    func setFromString(_ s: String) {
        let lower = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.hasPrefix("landscape") {
            required = .landscape
        } else if lower.hasPrefix("portrait") {
            required = .portrait
        }
    }
}
