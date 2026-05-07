import SwiftUI

enum UGColor {
    enum Surface {
        static let base = Color(red: 0, green: 0, blue: 0)
        static let subtle = Color(red: 0x0D / 255.0, green: 0x0D / 255.0, blue: 0x10 / 255.0)
        static let raised = Color(red: 0x1A / 255.0, green: 0x1A / 255.0, blue: 0x20 / 255.0)
        static let glass = Color(red: 0x14 / 255.0, green: 0x14 / 255.0, blue: 0x18 / 255.0).opacity(0.85)
        static let overlay = Color.black.opacity(0.55)
    }

    enum Text {
        static let primary = Color.white
        static let secondary = Color(red: 0xC8 / 255.0, green: 0xC8 / 255.0, blue: 0xD0 / 255.0)
        static let muted = Color(red: 0x8E / 255.0, green: 0x8E / 255.0, blue: 0x96 / 255.0)
    }

    enum Accent {
        static let primary = Color(red: 1.0, green: 0xC7 / 255.0, blue: 0)
        static let trailing = Color(red: 1.0, green: 0x7E / 255.0, blue: 0)
    }

    enum Feedback {
        static let danger = Color(red: 1.0, green: 0x4D / 255.0, blue: 0x6A / 255.0)
    }

    enum Border {
        static let divider = Color(red: 0x1F / 255.0, green: 0x1F / 255.0, blue: 0x22 / 255.0)
    }
}

extension LinearGradient {
    static var ugAccent: LinearGradient {
        LinearGradient(
            colors: [UGColor.Accent.primary, UGColor.Accent.trailing],
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

extension UGShadow.HaloSize {
    var alpha: Double {
        switch self {
        case .xl: 0.42
        case .lg: 0.26
        case .sm: 0.18
        }
    }

    var borderAlpha: Double {
        switch self {
        case .xl: 0.22
        case .lg: 0.16
        case .sm: 0.12
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .xl: UGRadius.xl
        case .lg, .sm: UGRadius.l
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .xl: 20
        case .lg: 14
        case .sm: 12
        }
    }

    var shadowYOffset: CGFloat {
        switch self {
        case .xl: 14
        case .lg: 12
        case .sm: 8
        }
    }
}

extension View {
    @ViewBuilder
    func ugShadow(_ token: UGShadow) -> some View {
        switch token {
        case .halo(let size, let c):
            shadow(color: c.opacity(size.alpha), radius: size.shadowRadius, x: 0, y: size.shadowYOffset)
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

    func haloChrome(_ color: Color, size: UGShadow.HaloSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: size.cornerRadius)
        return clipShape(shape)
            .overlay(shape.stroke(color.opacity(size.borderAlpha)))
            .ugShadow(.halo(size, color))
    }
}

enum UGFont {
    static let displayXL = Font.system(.largeTitle, weight: .black)
    static let display   = Font.system(.title, weight: .black)
    static let titleL    = Font.system(.title2, weight: .heavy)
    static let titleM    = Font.system(.title3, weight: .heavy)
    static let body      = Font.system(.subheadline)
    static let bodyS     = Font.system(.footnote, weight: .medium)
    static let label     = Font.system(.caption, weight: .semibold)
    static let caption   = Font.system(.caption2, weight: .bold)
}
