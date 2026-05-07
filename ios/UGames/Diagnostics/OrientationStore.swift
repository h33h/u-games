import Foundation
import SwiftUI

@MainActor
final class OrientationStore: ObservableObject {
    static let shared = OrientationStore()

    enum Required { case landscape, portrait }

    @Published var required: Required? = nil
    @Published var gameActive: Bool = false {
        didSet { OrientationLock.gameActive = gameActive }
    }

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

enum OrientationLock {
    nonisolated(unsafe) static var gameActive: Bool = false
}
