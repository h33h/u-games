import SwiftUI

/// U-Games premium theme tokens — names match the spec
/// (docs/superpowers/specs/2026-05-05-ui-ux-redesign-design.md).
enum UGColor {
    static let bg0 = Color(red: 0, green: 0, blue: 0)
    static let surface = Color(red: 0x0D / 255.0, green: 0x0D / 255.0, blue: 0x10 / 255.0)
    static let elevated = Color(red: 0x1A / 255.0, green: 0x1A / 255.0, blue: 0x20 / 255.0)
    static let divider = Color(red: 0x1F / 255.0, green: 0x1F / 255.0, blue: 0x22 / 255.0)

    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0xC8 / 255.0, green: 0xC8 / 255.0, blue: 0xD0 / 255.0)
    static let textMuted = Color(red: 0x7A / 255.0, green: 0x7A / 255.0, blue: 0x82 / 255.0)

    static let accent = Color(red: 1.0, green: 0xC7 / 255.0, blue: 0)
    static let accentEnd = Color(red: 1.0, green: 0x7E / 255.0, blue: 0)
    static let danger = Color(red: 1.0, green: 0x4D / 255.0, blue: 0x6A / 255.0)

    static let glassFallback = Color(red: 0x14 / 255.0, green: 0x14 / 255.0, blue: 0x18 / 255.0).opacity(0.85)

    static let haloAlpha: Double = 0.35
    static let haloBorderAlpha: Double = 0.18
}

extension LinearGradient {
    static var ugAccent: LinearGradient {
        LinearGradient(
            colors: [UGColor.accent, UGColor.accentEnd],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

/// Typography tokens. Sizes from the spec table.
enum UGFont {
    static let displayXL = Font.system(size: 34, weight: .black)
    static let display = Font.system(size: 30, weight: .black)
    static let titleL = Font.system(size: 24, weight: .heavy)
    static let titleM = Font.system(size: 18, weight: .heavy)
    static let body = Font.system(size: 15, weight: .regular)
    static let bodyS = Font.system(size: 13, weight: .medium)
    static let label = Font.system(size: 11, weight: .semibold)
    static let caption = Font.system(size: 10, weight: .bold)
}
