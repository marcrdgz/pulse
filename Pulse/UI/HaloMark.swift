import SwiftUI

/// The bare Pulse mark: a ring of light with a flare at its top right, drawn from
/// `design/mark-light.svg` and `mark-dark.svg` (a 44-unit box, ring radius 17, flare radius 4.5).
/// With `drawsIn`, the ring traces itself from the flare once and the flare lights up.
struct HaloMark: View {
    var size: CGFloat
    var drawsIn = false
    @State private var progress: CGFloat = 1
    @State private var isFlareLit = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let unit = size / 44
        ZStack {
            Circle()
                .trim(from: 0, to: progress)
                // Starts the trace at the flare, which sits 45° above the 3 o'clock start of a trim.
                .rotation(.degrees(-45))
                .stroke(
                    LinearGradient(colors: Brand.ring, startPoint: .topTrailing, endPoint: .bottomLeading),
                    style: StrokeStyle(lineWidth: 3.5 * unit, lineCap: .round)
                )
                .frame(width: 34 * unit, height: 34 * unit)
            Circle()
                .fill(Brand.glow.opacity(0.26))
                .frame(width: 16 * unit, height: 16 * unit)
                .scaleEffect(isFlareLit ? 1 : 0.2)
                .opacity(isFlareLit ? 1 : 0)
                .offset(x: 12.02 * unit, y: -12.02 * unit)
            Circle()
                .fill(Brand.flare)
                .frame(width: 9 * unit, height: 9 * unit)
                .scaleEffect(isFlareLit ? 1 : 0.2)
                .opacity(isFlareLit ? 1 : 0)
                .offset(x: 12.02 * unit, y: -12.02 * unit)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            guard drawsIn, !reduceMotion else { return }
            progress = 0
            isFlareLit = false
            withAnimation(.easeInOut(duration: 1.1)) { progress = 1 }
            withAnimation(.spring(duration: 0.5, bounce: 0.5).delay(0.95)) { isFlareLit = true }
        }
    }
}
