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

/// Single source of truth for every drop-shadow in the app. Each case
/// encodes color/opacity/radius/offset so call sites stay declarative
/// (`.ugShadow(.haloLg(halo))`) and visual changes happen in one place.
enum UGShadow {
    /// Hero/feature surfaces — biggest cards (Hero, StoryCard, Detail hero).
    case haloXL(Color)
    /// Standard cards (Tile, Wide, Square in grids and rows).
    case haloLg(Color)
    /// Compact media tiles (Detail screenshots, More-like-this).
    case haloSm(Color)
    /// Floating chrome (tab bar) — neutral black drop.
    case chrome
    /// Drop behind overlay text on imagery for legibility.
    case overlayText
    /// Soft accent glow for the active state (chips). Pass `nil` to disable.
    case glow(Color?)
    /// CTA button halo (▶ Play now).
    case cta(Color)
    /// Tiny stacked elements (StoryCard mini-covers).
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

/// Three card-art tiers that pair a rounded-corner radius with the
/// matching halo shadow token. Centralises the "clip + tinted border +
/// tinted drop shadow" decoration every game-art surface uses.
enum UGHaloSize {
    /// Hero / Story / Detail-hero (radius 22, XL drop).
    case xl
    /// Tile / Wide / Square (radius 16, Lg drop).
    case lg
    /// Compact media (Detail screenshot tile — radius 16, Sm drop).
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
    /// Standard "halo" decoration for a game-art surface: rounded clip
    /// + faint tinted stroke + tinted drop shadow. The same triplet
    /// every card had inlined.
    func haloChrome(_ color: Color, size: UGHaloSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: size.cornerRadius)
        return clipShape(shape)
            .overlay(shape.stroke(color.opacity(UGColor.haloBorderAlpha)))
            .ugShadow(size.shadow(color))
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
