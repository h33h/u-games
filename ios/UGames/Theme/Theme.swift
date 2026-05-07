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
    case haloXL(Color)
    case haloLg(Color)
    case haloSm(Color)
    case chrome
    case overlayText
    case glow(Color?)
    case cta(Color)
    case stack
}

extension View {
    @ViewBuilder
    func ugShadow(_ token: UGShadow) -> some View {
        switch token {
        case .haloXL(let c):
            shadow(color: c.opacity(UGColor.haloAlpha), radius: 20, x: 0, y: 14)
        case .haloLg(let c):
            shadow(color: c.opacity(UGColor.haloAlpha), radius: 14, x: 0, y: 12)
        case .haloSm(let c):
            shadow(color: c.opacity(UGColor.haloAlpha), radius: 12, x: 0, y: 8)
        case .chrome:
            shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 12)
        case .overlayText:
            shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 2)
        case .glow(let c):
            shadow(color: (c ?? .clear).opacity(0.4), radius: 8, x: 0, y: 0)
        case .cta(let c):
            shadow(color: c.opacity(0.5), radius: 18, x: 0, y: 8)
        case .stack:
            shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 2)
        }
    }
}

enum UGHaloSize {
    case xl
    case lg
    case sm

    var cornerRadius: CGFloat {
        switch self {
        case .xl: UGRadius.xl
        case .lg, .sm: UGRadius.l
        }
    }

    func shadow(_ color: Color) -> UGShadow {
        switch self {
        case .xl: .haloXL(color)
        case .lg: .haloLg(color)
        case .sm: .haloSm(color)
        }
    }
}

extension View {
    func haloChrome(_ color: Color, size: UGHaloSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: size.cornerRadius)
        return clipShape(shape)
            .overlay(shape.stroke(color.opacity(UGColor.haloBorderAlpha)))
            .ugShadow(size.shadow(color))
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
