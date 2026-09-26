//
//  ConfettiView.swift
//  Clima
//

import SwiftUI

/// One burst of confetti falling down the whole screen — the sign that the hidden
/// triple-tap on the dial's current icon has switched weather services.
///
/// Drawn in a `Canvas` driven by `TimelineView` rather than as a hundred-odd separate
/// views: every piece's position is worked out from the time since `start`, so there's
/// no per-piece state to animate and the whole thing is one layer to draw. It doesn't
/// take touches, so the screen underneath keeps working while it falls.
struct ConfettiView: View {
    /// When the burst began. Everything on screen is a function of the time since.
    let start: Date

    /// How long a burst lasts, including the fade at the end. The screen removes the view
    /// after this long.
    static let duration: Duration = .seconds(4)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Made once per burst — `@State`'s initial value is only evaluated when the view
    /// first appears — so the pieces don't reshuffle on every frame.
    @State private var pieces = Piece.burst(count: 140)

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                let total = Double(Self.duration.components.seconds)
                // Full strength until the last 0.8s, then fades out rather than vanishing.
                let fade = min(1, max(0, (total - elapsed) / 0.8))

                for piece in pieces {
                    draw(piece, at: elapsed, fade: fade, in: size, context: context)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ piece: Piece, at t: TimeInterval, fade: Double, in size: CGSize, context: GraphicsContext) {
        var context = context
        let position: CGPoint
        if reduceMotion {
            // With Reduce Motion on, the pieces appear scattered where they are and fade,
            // rather than raining down the screen.
            position = CGPoint(x: piece.x * size.width, y: piece.restingY * size.height)
        } else {
            // Starts above the top edge (staggered, so they arrive as a shower rather than
            // one line), falls under gravity, and sways side to side as it goes.
            let gravity = 260.0
            let y = piece.startY + piece.fallSpeed * t + 0.5 * gravity * t * t
            let sway = piece.swayAmount * sin(piece.swaySpeed * t + piece.phase)
            position = CGPoint(x: piece.x * size.width + sway, y: y)
        }

        context.opacity = fade
        context.translateBy(x: position.x, y: position.y)
        context.rotate(by: .radians(piece.phase + piece.spinSpeed * t))
        // Squashing the width back and forth reads as the paper flipping over in the air.
        context.scaleBy(x: cos(piece.flipSpeed * t + piece.phase), y: 1)

        let rect = CGRect(x: -piece.width / 2, y: -piece.height / 2, width: piece.width, height: piece.height)
        let path = piece.isRound ? Path(ellipseIn: rect) : Path(rect)
        context.fill(path, with: .color(piece.color))
    }
}

extension ConfettiView {
    /// One scrap of paper: where it starts, how it moves, and what it looks like — all
    /// picked at random once, when the burst is made.
    struct Piece {
        /// Across the screen, 0 at the left edge and 1 at the right.
        let x: Double
        /// Points above the top edge it starts from.
        let startY: Double
        /// Down the screen, 0–1, for the Reduce Motion version that doesn't fall.
        let restingY: Double
        let fallSpeed: Double
        let swayAmount: Double
        let swaySpeed: Double
        let spinSpeed: Double
        let flipSpeed: Double
        let phase: Double
        let width: Double
        let height: Double
        let isRound: Bool
        let color: Color

        /// System colours rather than fixed ones, so they stay bright against both the
        /// light and the dark page.
        private static let palette: [Color] = [.red, .orange, .yellow, .green, .mint, .blue, .purple, .pink]

        static func burst(count: Int) -> [Piece] {
            (0..<count).map { _ in
                let isRound = Double.random(in: 0...1) < 0.2
                let width = Double.random(in: 6...10)
                return Piece(
                    x: .random(in: 0...1),
                    startY: -.random(in: 20...420),
                    restingY: .random(in: 0.05...0.95),
                    fallSpeed: .random(in: 180...360),
                    swayAmount: .random(in: 8...28),
                    swaySpeed: .random(in: 2...5),
                    spinSpeed: .random(in: -4...4),
                    flipSpeed: .random(in: 4...10),
                    phase: .random(in: 0...(2 * .pi)),
                    width: width,
                    height: isRound ? width : .random(in: 10...16),
                    isRound: isRound,
                    color: palette.randomElement() ?? .red
                )
            }
        }
    }
}

// The canvas re-runs the burst each time the preview is refreshed.
#Preview {
    ConfettiView(start: .now)
        .background(Theme.canvas)
        .ignoresSafeArea()
}
