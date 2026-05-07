import SwiftUI

struct Skeleton: View {
    var cornerRadius: CGFloat = UGRadius.m

    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(UGColor.Surface.raised)
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    let bandW = max(60, w * 0.5)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.10),
                            Color.white.opacity(0),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: bandW, height: geo.size.height)
                    .offset(x: -bandW + phase * (w + bandW))
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear {
                guard !reduceMotion else { return }
                phase = 0
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
            .accessibilityHidden(true)
    }
}

struct SkeletonLine: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var cornerRadius: CGFloat = UGRadius.s

    var body: some View {
        Skeleton(cornerRadius: cornerRadius)
            .frame(width: width, height: height)
    }
}

struct SkeletonSectionHeader: View {
    var body: some View {
        HStack {
            SkeletonLine(width: 140, height: 18)
            Spacer()
            SkeletonLine(width: 56, height: 14)
        }
        .padding(.horizontal, UGSpace.l)
    }
}

struct SkeletonTileCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: UGSpace.s) {
            Skeleton(cornerRadius: UGRadius.l)
                .aspectRatio(16.0/10.0, contentMode: .fit)
            VStack(alignment: .leading, spacing: UGSpace.xs) {
                SkeletonLine(height: 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SkeletonLine(width: 90, height: 10)
            }
        }
    }
}

struct SkeletonWideCard: View {
    var body: some View {
        Skeleton(cornerRadius: UGRadius.l)
            .frame(width: UGSize.wideCardW, height: UGSize.wideCardH)
    }
}

struct SkeletonSquareCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: UGSpace.s) {
            Skeleton(cornerRadius: UGRadius.l)
                .frame(width: UGSize.squareCard, height: UGSize.squareCard)
            SkeletonLine(width: UGSize.squareCard * 0.7, height: 12)
        }
    }
}

struct SkeletonStoryCard: View {
    var body: some View {
        Skeleton(cornerRadius: UGRadius.xl)
            .frame(height: UGSize.storyH)
    }
}

struct SkeletonRowWide: View {
    var count: Int = 5

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: UGSpace.m) {
                ForEach(0..<count, id: \.self) { _ in SkeletonWideCard() }
            }
            .padding(.horizontal, UGSpace.l)
            .padding(.bottom, UGSpace.l)
        }
        .disabled(true)
        .accessibilityHidden(true)
    }
}

struct SkeletonRowSquare: View {
    var count: Int = 5

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: UGSpace.m) {
                ForEach(0..<count, id: \.self) { _ in SkeletonSquareCard() }
            }
            .padding(.horizontal, UGSpace.l)
            .padding(.bottom, UGSpace.l)
        }
        .disabled(true)
        .accessibilityHidden(true)
    }
}

struct SkeletonChipRow: View {
    var widths: [CGFloat] = [56, 84, 72, 96, 64, 80]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: UGSpace.s) {
                ForEach(Array(widths.enumerated()), id: \.offset) { _, w in
                    Skeleton(cornerRadius: 999)
                        .frame(width: w, height: 32)
                        .padding(.vertical, UGSpace.m)
                }
            }
            .padding(.horizontal, UGSpace.l)
        }
        .disabled(true)
        .accessibilityHidden(true)
    }
}

struct SkeletonTileGrid: View {
    var count: Int = 8
    private let columns = [GridItem(.adaptive(minimum: UGSize.tileGridMin, maximum: UGSize.tileGridMax), spacing: UGSpace.l)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: UGSpace.l) {
                ForEach(0..<count, id: \.self) { _ in SkeletonTileCard() }
            }
            .padding(.horizontal, UGSpace.l)
            .padding(.top, UGSpace.xs)
            .padding(.bottom, UGSize.tabBarInset)
        }
        .disabled(true)
        .accessibilityHidden(true)
    }
}

@available(iOS 17.0, *)
#Preview(traits: .fixedLayout(width: 360, height: 120)) {
    ZStack {
        Color.black.ignoresSafeArea()
        Skeleton()
            .padding()
            .frame(height: 120)
    }
}
