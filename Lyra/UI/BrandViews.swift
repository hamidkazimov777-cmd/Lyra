import SwiftUI

/// Premium brand mark for Lyra: Constellation of Lyra (Vega star) + Harmonic Audio Waves + AI Intelligence.
struct LyraLogoView: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let padX = size * 0.22
        let padY = size * 0.24
        let wUsable = size - 2 * padX
        let hUsable = size - 2 * padY
        let nx = (x - 29.5) / 97.0
        let ny = (y - 33.5) / 80.5
        return CGPoint(x: padX + nx * wUsable, y: padY + ny * hUsable)
    }

    var body: some View {
        let pPeak = pt(110.0, 33.5)
        let pRight = pt(126.5, 48.0)
        let pJunc = pt(95.5, 63.0)
        let pTL = pt(51.0, 67.5)
        let pBL = pt(29.5, 114.0)
        let pBR = pt(64.0, 114.0)

        return ZStack {
            // Squircle container
            RoundedRectangle(cornerRadius: size * 0.224)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.05, blue: 0.18),
                            Color(red: 0.08, green: 0.07, blue: 0.25),
                            Color(red: 0.05, green: 0.10, blue: 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.224)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.35, green: 0.78, blue: 1.0).opacity(0.6),
                                    Color(red: 0.58, green: 0.45, blue: 1.0).opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(1, size * 0.015)
                        )
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.6 : 0.25), radius: size * 0.1, x: 0, y: size * 0.04)

            // Constellation Lyra & AI Soundwave Emblem
            ZStack {
                // Ambient core glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.35, green: 0.78, blue: 1.0).opacity(0.4),
                                Color(red: 0.58, green: 0.45, blue: 1.0).opacity(0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.35
                        )
                    )
                    .frame(width: size * 0.7, height: size * 0.7)

                // Geometric constellation lines (Lyra triangle & parallelogram)
                Path { path in
                    // Triangle
                    path.move(to: pPeak)
                    path.addLine(to: pRight)
                    path.addLine(to: pJunc)
                    path.closeSubpath()

                    // Parallelogram
                    path.move(to: pTL)
                    path.addLine(to: pJunc)
                    path.addLine(to: pBR)
                    path.addLine(to: pBL)
                    path.closeSubpath()
                }
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.70, green: 0.88, blue: 1.0),
                            Color(red: 0.38, green: 0.65, blue: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: max(1.2, size * 0.015)
                )

                // Stars in the constellation
                Group {
                    // Vega: Main brilliant star with a luminous cross flare
                    ZStack {
                        // Halo
                        Circle()
                            .fill(Color(red: 0.45, green: 0.80, blue: 1.0).opacity(0.35))
                            .frame(width: size * 0.16, height: size * 0.16)

                        // Cross diffraction spikes
                        Rectangle()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: size * 0.14, height: max(1, size * 0.008))
                        Rectangle()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: max(1, size * 0.008), height: size * 0.14)

                        // Core
                        Circle()
                            .fill(Color.white)
                            .frame(width: size * 0.05, height: size * 0.05)
                            .shadow(color: Color(red: 0.45, green: 0.85, blue: 1.0), radius: size * 0.03)
                    }
                    .position(pPeak)

                    // Other 5 constellation stars
                    Circle().fill(Color.white).frame(width: size * 0.035, height: size * 0.035).position(pRight)
                    Circle().fill(Color.white).frame(width: size * 0.035, height: size * 0.035).position(pJunc)
                    Circle().fill(Color.white).frame(width: size * 0.035, height: size * 0.035).position(pTL)
                    Circle().fill(Color.white).frame(width: size * 0.038, height: size * 0.038).position(pBL)
                    Circle().fill(Color.white).frame(width: size * 0.038, height: size * 0.038).position(pBR)
                }

                // AI Voice waveform arcs in the center
                HStack(spacing: size * 0.02) {
                    RoundedRectangle(cornerRadius: size * 0.01)
                        .fill(Color(red: 0.35, green: 0.78, blue: 1.0).opacity(0.85))
                        .frame(width: size * 0.022, height: size * 0.10)
                    RoundedRectangle(cornerRadius: size * 0.01)
                        .fill(Color(red: 0.48, green: 0.65, blue: 1.0))
                        .frame(width: size * 0.022, height: size * 0.18)
                    RoundedRectangle(cornerRadius: size * 0.01)
                        .fill(Color(red: 0.60, green: 0.50, blue: 1.0))
                        .frame(width: size * 0.025, height: size * 0.26)
                    RoundedRectangle(cornerRadius: size * 0.01)
                        .fill(Color(red: 0.48, green: 0.65, blue: 1.0))
                        .frame(width: size * 0.022, height: size * 0.18)
                    RoundedRectangle(cornerRadius: size * 0.01)
                        .fill(Color(red: 0.35, green: 0.78, blue: 1.0).opacity(0.85))
                        .frame(width: size * 0.022, height: size * 0.10)
                }
                .position(x: size * 0.50, y: size * 0.54)
            }
        }
    }
}
