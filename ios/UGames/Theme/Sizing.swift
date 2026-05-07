import CoreGraphics

/// Dimensional design tokens. The rhythm tokens (`UGSpace`,
/// `UGRadius`) sit on a strict 4pt grid — every padding, spacing, and
/// corner in the app picks one of these values, or composes two
/// (`UGSpace.l + UGSpace.s`) for the rare in-between. No custom-named
/// tiers; if a token doesn't fit, the call site uses a raw `CGFloat`
/// with a comment explaining why.
///
/// Component dimensions (avatars, button discs, card frames) live in
/// `UGSize` because they're contracts of specific components — they
/// don't share the rhythm grid and can be off-grid when the design
/// calls for it.

/// 4pt-grid spacing scale. Increments of 4 from 4 → 32.
enum UGSpace {
    /// 4pt
    static let xs: CGFloat = 4
    /// 8pt — base unit.
    static let s: CGFloat = 8
    /// 12pt
    static let m: CGFloat = 12
    /// 16pt — screen edge / section internal.
    static let l: CGFloat = 16
    /// 20pt
    static let xl: CGFloat = 20
    /// 24pt
    static let xxl: CGFloat = 24
    /// 28pt
    static let xxxl: CGFloat = 28
    /// 32pt
    static let huge: CGFloat = 32
}

/// Corner radii on the same 4pt grid.
enum UGRadius {
    /// 8pt — story-card mini covers.
    static let s: CGFloat = 8
    /// 12pt — neutral surface card / search bar / inline CTA.
    static let m: CGFloat = 12
    /// 16pt — standard card / screenshot tile.
    static let l: CGFloat = 16
    /// 24pt — hero / story / detail-hero.
    static let xl: CGFloat = 24
    /// 28pt — floating tab-bar pill.
    static let xxl: CGFloat = 28
}

/// Component dimensions: avatars, circular buttons, card frames,
/// chrome heights. These are component contracts, not rhythm — they
/// can sit off the 4pt grid when the design needs it.
enum UGSize {
    // MARK: Avatars
    /// 38pt — Home greeting avatar.
    static let avatarS: CGFloat = 38
    /// 96pt — Profile hero avatar / About app logo.
    static let avatarL: CGFloat = 96

    // MARK: Circular icon buttons
    /// 30pt — tile heart toggle.
    static let buttonSm: CGFloat = 30
    /// 32pt — Hero overlay icons.
    static let buttonM: CGFloat = 32
    /// 36pt — Detail hero / fullscreen close.
    static let buttonL: CGFloat = 36

    // MARK: Card frames
    /// 130×130 — square category card.
    static let squareCard: CGFloat = 130
    /// 140×96 — wide card.
    static let wideCardW: CGFloat = 140
    static let wideCardH: CGFloat = 96
    /// 220×124 — Detail screenshot tile.
    static let screenshotW: CGFloat = 220
    static let screenshotH: CGFloat = 124
    /// 160×140 — "More like this" similar-tile (skeleton placeholder
    /// height; live tiles are width-only with auto height).
    static let similarTileW: CGFloat = 160
    static let similarTileH: CGFloat = 140
    /// 48pt — tile title+meta block, fixed so cards align across rows.
    static let tileTitleH: CGFloat = 48
    /// 160 / 220 — `LazyVGrid(.adaptive)` bounds for tile grids
    /// (Browse / Favorites). The grid auto-fits as many columns as
    /// will fit each tile within these limits.
    static let tileGridMin: CGFloat = 160
    static let tileGridMax: CGFloat = 220

    // MARK: Section heights
    /// 300pt — Home Hero card.
    static let heroH: CGFloat = 300
    /// 360pt — Detail hero (with stretchy header).
    static let heroDetailH: CGFloat = 360
    /// 160pt — Story card.
    static let storyH: CGFloat = 160
    /// 62pt — Floating tab bar.
    static let tabBarH: CGFloat = 62

    // MARK: Layout reservations
    /// 96pt — bottom inset reserved for the floating tab bar so the
    /// last list item isn't tucked under the chrome.
    static let tabBarInset: CGFloat = 96

    // MARK: Misc
    /// 42pt — story-card mini cover thumbnail.
    static let storyMiniCover: CGFloat = 42
    /// 24pt — settings-row icon column width.
    static let settingsIconCol: CGFloat = 24
    /// 110pt — Detail Information-block label column.
    static let infoLabelCol: CGFloat = 110
}
