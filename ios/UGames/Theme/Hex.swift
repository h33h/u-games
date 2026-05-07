import SwiftUI

extension Color {
    init?(hex: String?) {
        guard let raw = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let cleaned = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        guard let value = UInt64(cleaned, radix: 16) else { return nil }
        switch cleaned.count {
        case 6:
            let r = Double((value >> 16) & 0xFF) / 255.0
            let g = Double((value >> 8) & 0xFF) / 255.0
            let b = Double(value & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b)
        case 8:
            let a = Double((value >> 24) & 0xFF) / 255.0
            let r = Double((value >> 16) & 0xFF) / 255.0
            let g = Double((value >> 8) & 0xFF) / 255.0
            let b = Double(value & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b, opacity: a)
        default:
            return nil
        }
    }
}
