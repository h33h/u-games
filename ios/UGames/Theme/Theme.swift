import SwiftUI

enum UGColor {
    static let bg0 = Color(red: 0, green: 0, blue: 0)
    static let surface = Color(red: 0x0D / 255.0, green: 0x0D / 255.0, blue: 0x10 / 255.0)
    static let elevated = Color(red: 0x1A / 255.0, green: 0x1A / 255.0, blue: 0x20 / 255.0)
    static let divider = Color(red: 0x1F / 255.0, green: 0x1F / 255.0, blue: 0x22 / 255.0)
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0xC8 / 255.0, green: 0xC8 / 255.0, blue: 0xD0 / 255.0)
    static let textMuted = Color(red: 0x8E / 255.0, green: 0x8E / 255.0, blue: 0x96 / 255.0)
    static let accent = Color(red: 1.0, green: 0xC7 / 255.0, blue: 0)
    static let accentEnd = Color(red: 1.0, green: 0x7E / 255.0, blue: 0)
    static let danger = Color(red: 1.0, green: 0x4D / 255.0, blue: 0x6A / 255.0)
    static let glassFallback = Color(red: 0x14 / 255.0, green: 0x14 / 255.0, blue: 0x18 / 255.0).opacity(0.85)
    static let overlayBg = Color.black.opacity(0.55)
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

enum UGShadow {
    case halo(HaloSize, Color)
    case elevation(Elevation)
    case glow(GlowIntensity, Color)

    enum HaloSize { case sm, lg, xl }
    enum Elevation { case text, stacked, surface }
    enum GlowIntensity { case subtle, strong }
}

extension View {
    @ViewBuilder
    func ugShadow(_ token: UGShadow) -> some View {
        switch token {
        case .halo(let size, let c):
            switch size {
            case .xl: shadow(color: c.opacity(UGColor.haloAlpha), radius: 20, x: 0, y: 14)
            case .lg: shadow(color: c.opacity(UGColor.haloAlpha), radius: 14, x: 0, y: 12)
            case .sm: shadow(color: c.opacity(UGColor.haloAlpha), radius: 12, x: 0, y: 8)
            }
        case .elevation(let level):
            switch level {
            case .text:    shadow(color: .black.opacity(0.6),  radius: 6,  x: 0, y: 2)
            case .stacked: shadow(color: .black.opacity(0.45), radius: 6,  x: 0, y: 2)
            case .surface: shadow(color: .black.opacity(0.5),  radius: 16, x: 0, y: 12)
            }
        case .glow(let intensity, let c):
            switch intensity {
            case .subtle: shadow(color: c.opacity(0.4), radius: 8,  x: 0, y: 0)
            case .strong: shadow(color: c.opacity(0.5), radius: 18, x: 0, y: 8)
            }
        }
    }
}

extension UGShadow.HaloSize {
    var cornerRadius: CGFloat {
        switch self {
        case .xl: UGRadius.xl
        case .lg, .sm: UGRadius.l
        }
    }
}

extension View {
    func haloChrome(_ color: Color, size: UGShadow.HaloSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: size.cornerRadius)
        return clipShape(shape)
            .overlay(shape.stroke(color.opacity(UGColor.haloBorderAlpha)))
            .ugShadow(.halo(size, color))
    }
}

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
