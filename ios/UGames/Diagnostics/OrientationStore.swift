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
        switch s.lowercased() {
        case "landscape": required = .landscape
        case "portrait": required = .portrait
        default: break
        }
    }
}

enum OrientationLock {
    nonisolated(unsafe) static var gameActive: Bool = false
}
