//
//  DialView.swift
//  Clima
//

import SwiftUI

/// The weather dial: a wheel of condition icons, separated by hairline spokes, that
/// ROTATES behind a fixed umbrella-shaped window (the wheel's own top half). Only 3
/// icons are ever visible — the current condition centred under the pointer, with its
/// two neighbours showing on either side.
///
/// Styled as a measuring instrument rather than an illustration: a flat canopy, a
/// graduated tick scale around the rim, and the single red pointer as the only colour
/// on the screen.
struct DialView: View {
    /// The condition to point at, or nil when there's no reading to show.
    ///
    /// Nil is a real state, not a missing value to be defaulted away: the wheel stays
    /// where it is and NO icon is lit, so the instrument reads as "nothing measured"
    /// rather than confidently indicating whichever condition a default landed on.
    let condition: WeatherCondition?
    var onRefresh: () -> Void = {}

    /// How much bigger or smaller this screen is than the iPhone 16 Pro this dial was
    /// tuned on (see `Theme.tunedScreenWidth`). Every size below multiplies by this, so
    /// the whole assembly grows or shrinks together on a different iPhone.
    @Environment(\.deviceScale) private var deviceScale

    /// The wheel's rotation, in degrees. Starts aligned to .clear so there's somewhere
    /// to animate *from* on first appearance, rather than materialising already settled.
    @State private var wheelRotation: Double = -WeatherCondition.clear.angle
    /// Turns the refresh glyph along with the wheel, so the button visibly drives it.
    @State private var refreshSpin: Double = 0

    // MARK: - Sizing
    //
    // Every constant here is the exact measurement this dial was tuned at (an iPhone 16
    // Pro, 402pt wide) — the instance properties below multiply each one by
    // `deviceScale` so the dial fills the same proportion of the screen everywhere.

    private static let baseDiameter: CGFloat = 380
    private static let baseHubDiameter: CGFloat = 60
    private static let baseIconDiameter: CGFloat = 70
    private static let baseHubRingWidth: CGFloat = 5.5
    private static let baseHubRingGap: CGFloat = 10
    private static let baseRefreshGlyphWidth: CGFloat = 26
    /// The pointer's tip: a wide, shallow arrowhead at a flat 2:1, which reads as
    /// pointing at the rim rather than perching on it now that the rim trace under it
    /// is finer. One size for both pages — note that on the dark page this triangle is
    /// also the lamp casting `pointerBeam`, and the beam's mouth is built from these
    /// two numbers, so changing them re-shapes the cone as well.
    private static let basePointerTriangleWidth: CGFloat = 32
    private static let basePointerTriangleHeight: CGFloat = 16

    /// The 3 visible wedges (see `canopyShape`'s halfAngle) never change with this — it
    /// only decides how much of the canopy's own rim and hub sit inside them.
    ///
    /// Exposed as a function of scale, not an instance property, because
    /// `WeatherDialScreen` needs this same number for its own layout — how far the
    /// canopy should bleed past the page's margin — without building a `DialView` of
    /// its own just to ask it.
    static func diameter(scale: CGFloat) -> CGFloat { baseDiameter * scale }
    /// How far the hub hangs below the canopy's layout frame — the screen below needs
    /// to clear this before placing anything else. Needed externally for the same
    /// reason as `diameter(scale:)`.
    static func hubOverhang(scale: CGFloat) -> CGFloat { baseHubDiameter * scale * 0.75 }
    /// The canopy's widest *painted* point, which falls a few points short of
    /// `diameter`. The fan's two rim ends sit at ±halfAngle either side of the top, so
    /// the shape only ever reaches `radius · sin(halfAngle)` across — the rest of the
    /// layout frame is empty air beside the curve.
    ///
    /// `WeatherDialScreen` lines the forecast panels up with this rather than with the
    /// frame, so their edges meet the canopy the eye actually sees instead of running
    /// visibly wider than it.
    static func canopyWidth(scale: CGFloat) -> CGFloat {
        diameter(scale: scale) * sin(1.5 * stepAngle * .pi / 180)
    }

    private var diameter: CGFloat { Self.diameter(scale: deviceScale) }
    private var hubDiameter: CGFloat { Self.baseHubDiameter * deviceScale }

    /// Where the condition icons sit on the wheel. The pointer reads this too, so that
    /// its break lines up with the icon it points at.
    private var iconDiameter: CGFloat { Self.baseIconDiameter * deviceScale }
    private var iconInset: CGFloat { diameter / 9 }

    /// The bezel ring around the button.
    private var hubRingWidth: CGFloat { Self.baseHubRingWidth * deviceScale }
    /// Where the imaginary light sits, in the same "0 = top, clockwise" convention the
    /// dial's angles use. An angle rather than a length, so — unlike everything else on
    /// this page — it does NOT scale with screen size. Change this one number to swing
    /// the highlights around the ring; -35 puts the main catch at the upper left.
    private static let hubLightAngle: Double = -35
    private var hubRingDiameter: CGFloat { hubDiameter + 2 * hubRingWidth }
    /// Page colour left showing between the bezel and the canopy's notch, so the two
    /// never touch.
    private var hubRingGap: CGFloat { Self.baseHubRingGap * deviceScale }
    /// The hole the canopy leaves for the whole assembly: bezel plus that gap.
    private var hubGapDiameter: CGFloat { hubRingDiameter + 2 * hubRingGap }

    /// The refresh glyph's width, which is also its ring's outer diameter — a little
    /// under half the button face it sits on. Its height follows from
    /// `RefreshGlyph.aspectRatio`, since the arrowhead makes it taller than it is wide.
    private var refreshGlyphWidth: CGFloat { Self.baseRefreshGlyphWidth * deviceScale }

    private var pointerTriangleWidth: CGFloat { Self.basePointerTriangleWidth * deviceScale }
    private var pointerTriangleHeight: CGFloat { Self.basePointerTriangleHeight * deviceScale }

    /// Static so `canopyWidth(scale:)` can reach it without a `DialView` instance —
    /// one definition of the wedge angle, shared by the shape and by the layout number
    /// the screen reads back.
    private static let stepAngle = 360.0 / Double(WeatherCondition.allCases.count)

    /// Centre of the refresh hub, in the same coordinate space as the canopy: on the
    /// canopy's bottom edge, a quarter of it tucked up inside.
    private var hubCenter: CGPoint {
        CGPoint(x: diameter / 2, y: diameter / 2 + hubDiameter / 4)
    }

    var body: some View {
        ZStack(alignment: .top) {
            wheel
                .rotationEffect(.degrees(wheelRotation))
                // Trims the canopy to exactly the 3 visible wedges — the current
                // condition's wedge plus one full wedge either side — instead of a full
                // half-circle that hints at room for more. Its bottom point is rounded
                // off into a smooth curve around the refresh hub.
                .clipShape(canopyShape)

            // Over the wheel, so the light falls ON the icons; under everything below,
            // so the rim shading and the pointer itself still sit on top of it.
            pointerBeam

            canopyInnerShadow

            // Over the shadow, not under it. The rim shading is heaviest exactly where
            // the tip sits, so underneath it the tip read as a darkened version of
            // `Theme.pointerTriangle` rather than as the colour itself — and the shaft
            // below, which has always drawn above the shadow, didn't match it. Still
            // under the rim trace and the hub, so only its relationship to the shadow
            // has changed.
            pointerTriangle

            // The page-coloured gap, moved ahead of the rim trace below rather than
            // after it, so the trace's closing edge (see `.outline`) paints on top of
            // this flat disc instead of being painted over by it.
            Circle()
                .fill(Theme.canvas)
                .frame(width: hubGapDiameter, height: hubGapDiameter)
                .position(hubCenter)

            // The canopy's own rim trace — NOT the refresh button, which is a
            // separate element with its own bezel. `.outline` stops at the two bottom
            // corners rather than continuing under the hub notch, so this line never
            // rings the button from below.
            canopyShape.outline
                .stroke(Theme.canopyOutline, lineWidth: 1.5 * deviceScale)
                .frame(width: diameter, height: diameter)

            // Just the connecting piece over the top of the hub — the same two corners
            // `.outline` stops at, joined the short way through the canopy's interior
            // rather than the long way under the button. Same colour and width as the
            // trace above, so the two read as one continuous line meeting the button
            // from above, not a second line added on top of it.
            canopyShape.topArc
                .stroke(Theme.canopyOutline, lineWidth: 1.5 * deviceScale)
                .frame(width: diameter, height: diameter)

            pointerShaft

            refreshButton
                .position(hubCenter)
        }
        // Collapse the enclosing box down to just the visible dome, so the clipped
        // (invisible) bottom half of the wheel — and the part of the hub hanging below
        // it — don't take up layout space underneath.
        .frame(width: diameter, height: diameter / 2, alignment: .top)
        .onAppear { animate(to: condition) }
        .onChange(of: condition) { _, newCondition in animate(to: newCondition) }
    }

    // MARK: - The canopy

    private var canopyShape: Fan {
        Fan(
            halfAngle: 1.5 * Self.stepAngle,
            notchCenter: hubCenter,
            notchRadius: hubGapDiameter / 2,
            cornerRadius: 12 * deviceScale,
            notchCornerRadius: 8 * deviceScale
        )
    }

    private var canopyInnerShadow: some View {
        InnerShadow(shape: canopyShape.omittingHubCurve, scale: deviceScale)
            .frame(width: diameter, height: diameter)
    }

    // MARK: - The rotating wheel — face, scale, icons, spokes

    private var wheel: some View {
        ZStack {
            Circle()
                .fill(Theme.dialFace)

            ForEach(WeatherCondition.allCases, id: \.self) { c in
                spoke(offset: iconInset) {
                    Image(c.iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconDiameter, height: iconDiameter)
                        // Compares against an optional, so when there's no reading this
                        // is false for every icon and none of them lights up.
                        .foregroundStyle(c == condition ? Theme.dialIconSelected : Theme.dialIconInactive)
                }
                .rotationEffect(.degrees(c.angle))

                // One separator per icon, halfway to the next one, running from the rim
                // in to the canopy's centre.
                spoke(offset: 0) {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: deviceScale, height: diameter / 2)
                }
                .rotationEffect(.degrees(c.angle + Self.stepAngle / 2))
            }
        }
        .frame(width: diameter, height: diameter)
        // Match the spin, so the incoming icon darkens as it arrives under the pointer
        // instead of switching colour the instant the data changes.
        .animation(.easeInOut(duration: 0.75), value: condition)
    }

    /// Pins content at a fixed distance from the top of a full-height column so
    /// rotating it swings the content around the wheel's true centre, not the content's
    /// own tiny bounds.
    private func spoke<Content: View>(offset: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack {
            content()
                .offset(y: offset)
            Spacer()
        }
        .frame(height: diameter)
    }

    // MARK: - The fixed pointer marking the selected icon

    /// The rim end of the instrument's index mark. Drawn over `canopyInnerShadow`, so it
    /// holds its own colour where the rim shading is heaviest — the same treatment
    /// `pointerShaft` already had, so both ends of the mark read as one.
    private var pointerTriangle: some View {
        Triangle()
            .fill(Theme.pointerTriangle)
            .frame(width: pointerTriangleWidth, height: pointerTriangleHeight)
    }

    /// The light the pointer throws down the canopy in dark mode: a cone leaving the
    /// triangle already as wide as the triangle itself, spreading as it falls, and spent
    /// just past the icon below — a street lamp lighting the road beneath it.
    ///
    /// Clipped to the canopy so none of it spills onto the page, and ADDED to what's
    /// underneath (`plusLighter`) rather than painted over it, so it lifts the canopy and
    /// the icon the way light does instead of tinting them the way a wash of colour
    /// would. In light mode `Theme.pointerBeam` is fully transparent, so this whole layer
    /// draws nothing and the pointer goes back to being a mark printed on the dial.
    private var pointerBeam: some View {
        // The light leaves the lamp where the lamp ends — the triangle's tip — carrying
        // the triangle's full width with it, rather than pinching to a point there.
        let mouthY = pointerTriangleHeight
        // Spent a quarter of an icon past the icon's own bottom edge: far enough that
        // the light clearly falls ON the reading rather than stopping at it, close
        // enough that it never reaches the refresh hub below.
        let reach = iconInset + iconDiameter * 1.25
        let length = reach - mouthY
        // Where the icon's middle falls along that run, so the gradient's mid stop can
        // be pinned to the thing the beam exists to light rather than to an arbitrary
        // fraction that drifts every time the reach is retuned.
        let iconMidStop = (iconInset + iconDiameter / 2 - mouthY) / length

        return LightBeam(
            mouthY: mouthY,
            mouthWidth: pointerTriangleWidth,
            halfAngle: 19,
            length: length
        )
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Theme.pointerBeam.opacity(0.30), location: 0.00),
                        .init(color: Theme.pointerBeam.opacity(0.20), location: iconMidStop),
                        .init(color: Theme.pointerBeam.opacity(0.00), location: 1.00),
                    ],
                    // Pinned to the beam's own span rather than to the frame's top and
                    // bottom — the frame is the full dial, most of which the beam never
                    // reaches, so `.top`/`.bottom` would leave the fade barely started.
                    startPoint: UnitPoint(x: 0.5, y: mouthY / diameter),
                    endPoint: UnitPoint(x: 0.5, y: (mouthY + length) / diameter)
                )
            )
            // Softens the wedge's straight sides into a glow, rather than a hard-edged
            // shape of colour sitting on the canopy.
            .blur(radius: 9 * deviceScale)
            .frame(width: diameter, height: diameter)
            .clipShape(canopyShape)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    /// The hairline running from just below the triangle down to the hub, tying the
    /// reading to the control that refreshes it. It breaks around the icon it points
    /// at, the way a leader line in a technical drawing yields to the thing it labels,
    /// so the reading itself stays unobstructed. A leading spacer the triangle's own
    /// height stands in for it, keeping this piece aligned to the same spot the
    /// combined pointer used to occupy.
    private var pointerShaft: some View {
        let hubTop = hubCenter.y - hubGapDiameter / 2

        return VStack(spacing: 0) {
            Color.clear
                .frame(width: pointerTriangleWidth, height: pointerTriangleHeight)

            pointerLine(height: iconInset - pointerTriangleHeight)

            Color.clear
                .frame(height: iconDiameter)

            pointerLine(height: hubTop - iconInset - iconDiameter)
        }
    }

    private func pointerLine(height: CGFloat) -> some View {
        Rectangle()
            .fill(Theme.pointerLine)
            .frame(width: 1.5 * deviceScale, height: max(height, 0))
    }

    // MARK: - The refresh hub

    /// A specular pass laid over the bezel's base gradient: a bright arc where the ring
    /// faces the light, a weaker one opposite it where the page bounces light back, and
    /// dark arcs on the two flanks between them. It paints white and black over the base
    /// colours rather than introducing new ones, so the ring's own palette still reads.
    ///
    /// Every stop fades to a transparent version of its OWN colour rather than to
    /// `.clear`, which would interpolate through transparent black and dirty the
    /// highlights on the way out.
    private var hubRingLight: AngularGradient {
        AngularGradient(
            stops: [
                .init(color: .white.opacity(0.65), location: 0.00),
                .init(color: .white.opacity(0.00), location: 0.10),
                .init(color: .black.opacity(0.00), location: 0.15),
                .init(color: .black.opacity(0.30), location: 0.25),
                .init(color: .black.opacity(0.00), location: 0.35),
                .init(color: .white.opacity(0.00), location: 0.40),
                .init(color: .white.opacity(0.28), location: 0.50),
                .init(color: .white.opacity(0.00), location: 0.60),
                .init(color: .black.opacity(0.00), location: 0.65),
                .init(color: .black.opacity(0.30), location: 0.75),
                .init(color: .black.opacity(0.00), location: 0.85),
                .init(color: .white.opacity(0.00), location: 0.90),
                .init(color: .white.opacity(0.65), location: 1.00),
            ],
            center: .center,
            // AngularGradient starts at 3 o'clock, so -90 puts location 0 at the top
            // before the light angle swings it round.
            angle: .degrees(Self.hubLightAngle - 90)
        )
    }

    private var refreshButton: some View {
        Button(action: handleRefreshTap) {
            ZStack {
                // The bezel, brightest where it meets the button and falling away to
                // shadow at its outer edge.
                Circle()
                    .strokeBorder(
                        RadialGradient(
                            colors: [Theme.hubRingInner, Theme.hubRingOuter],
                            center: .center,
                            startRadius: hubDiameter / 2,
                            endRadius: hubRingDiameter / 2
                        ),
                        lineWidth: hubRingWidth
                    )
                    .frame(width: hubRingDiameter, height: hubRingDiameter)
                    .overlay(
                        Circle()
                            .strokeBorder(hubRingLight, lineWidth: hubRingWidth)
                            .frame(width: hubRingDiameter, height: hubRingDiameter)
                    )

                // The button face. Two shadows rather than one is what reads as height:
                // a wide ambient one for the lift, and a tight contact one that keeps it
                // anchored to the bezel instead of floating free of it.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.hubFaceCenter, Theme.hubFaceEdge],
                            center: .center,
                            startRadius: 0,
                            endRadius: hubDiameter / 2
                        )
                    )
                    .frame(width: hubDiameter, height: hubDiameter)
                    .shadow(color: .black.opacity(0.30), radius: 6 * deviceScale, y: 4 * deviceScale)
                    .shadow(color: .black.opacity(0.18), radius: 1.5 * deviceScale, y: 1 * deviceScale)

                // Round caps and joins throughout: the reference's arm ends and its
                // arrowhead are all softened, which is also what the rest of the app's
                // moulded surfaces do.
                RefreshGlyph()
                    .stroke(
                        Theme.hubGlyph,
                        style: StrokeStyle(
                            lineWidth: RefreshGlyph.strokeWidth(forWidth: refreshGlyphWidth),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(
                        width: refreshGlyphWidth,
                        height: refreshGlyphWidth * RefreshGlyph.aspectRatio
                    )
                    // What makes a glyph barely a shade lighter than the face read at
                    // all. Straight down, like every other shadow in the app.
                    .shadow(color: .black.opacity(0.28), radius: 1.2 * deviceScale, y: 1.2 * deviceScale)
                    .rotationEffect(.degrees(refreshSpin), anchor: RefreshGlyph.ringCenterUnitPoint)
            }
        }
        .contentShape(Circle())
        .buttonStyle(.plain)
        .frame(width: hubRingDiameter, height: hubRingDiameter)
        .accessibilityLabel("Refresh weather")
    }

    // MARK: - Motion

    private func animate(to newCondition: WeatherCondition?) {
        // Nothing to point at — leave the wheel where it is. Spinning back to a default
        // would be motion that means nothing, and the unlit icons already say there's no
        // reading.
        guard let newCondition else { return }
        // A spring, rather than a plain ease, so the wheel overshoots its target
        // slightly and settles back into place instead of just easing to a stop.
        //
        // The click rides the animation's completion rather than firing with it, so it
        // marks the wheel ARRIVING on the icon — the detent at the end of the turn, the
        // way a rotary switch clicks when it drops into position. Fired up front it
        // would land while the wheel was still visibly moving.
        withAnimation(.spring(response: 0.75, dampingFraction: 0.55)) {
            wheelRotation = -newCondition.angle
        } completion: {
            SoundPlayer.shared.play(.wheelClick)
        }
    }

    /// Tapping refresh should always replay the spin-and-land animation, even if the
    /// condition turns out to be unchanged — a plain `animate(to:)` wouldn't animate at
    /// all in that case, since the target angle would already match. Spinning one extra
    /// full turn past the target guarantees visible motion every time, landing on the
    /// exact same spot a full rotation later.
    ///
    /// Both turn CLOCKWISE — a positive angle, since SwiftUI measures rotation with the
    /// y-axis pointing down — and they turn together, by the same amount, in the same
    /// call. That direction is the refresh glyph's: its arrowhead chases its own tail
    /// clockwise, and a button whose mark points one way while the button spins the
    /// other reads as a mistake. The wheel follows the button rather than the other way
    /// round, because the button is what the finger pushed.
    private func handleRefreshTap() {
        // Under the finger, not at the end of the spin: this one is the button being
        // pressed, so it has to answer the touch immediately. The wheel's own click
        // follows a beat later, when the turn it starts here comes to rest.
        SoundPlayer.shared.play(.refresh)
        withAnimation(.spring(response: 0.75, dampingFraction: 0.55)) {
            wheelRotation += 360
            refreshSpin += 360
        } completion: {
            SoundPlayer.shared.play(.wheelClick)
        }
        onRefresh()
    }
}

/// The wedge of light the pointer casts, centred on the rect's vertical centre line: a
/// trapezoid that starts `mouthWidth` across at the lamp and widens by `halfAngle` as it
/// falls, cut off flat at `length` — by which point the gradient filling it has faded to
/// nothing, so neither flat end ever shows as an edge.
///
/// A mouth rather than a point, because a lamp with a housing throws light from the
/// whole width of that housing; pinched to a point it read as a thin spike leaking out
/// of the triangle's tip rather than as a beam the pointer casts.
///
/// Measured from the top of the rect rather than centred in it, because it's drawn in
/// the dial's own full-diameter coordinate space alongside `Fan`, where its mouth has to
/// land on the pointer.
private struct LightBeam: Shape {
    /// How far below the top of the rect the light leaves the lamp.
    var mouthY: CGFloat
    /// How wide the beam already is there, before any spreading.
    var mouthWidth: CGFloat
    /// Half the beam's spread, in degrees.
    var halfAngle: Double
    /// How far below the mouth the beam reaches.
    var length: CGFloat

    func path(in rect: CGRect) -> Path {
        let halfMouth = mouthWidth / 2
        let halfFoot = halfMouth + length * tan(halfAngle * .pi / 180)
        let footY = mouthY + length

        var path = Path()
        path.move(to: CGPoint(x: rect.midX - halfMouth, y: mouthY))
        path.addLine(to: CGPoint(x: rect.midX + halfMouth, y: mouthY))
        path.addLine(to: CGPoint(x: rect.midX + halfFoot, y: footY))
        path.addLine(to: CGPoint(x: rect.midX - halfFoot, y: footY))
        path.closeSubpath()
        return path
    }
}

/// A pie-slice/sector shape spanning `halfAngle` degrees either side of top-centre,
/// used to trim the wheel down to just its visible wedges. Rather than converging to a
/// sharp point at the bottom, its two straight sides are cut short where they reach
/// `notchRadius` of `notchCenter`, and joined by a smooth curve around that circle —
/// rounding the canopy's bottom point into a curve that hugs the refresh hub.
///
/// All four corners are rounded the same way: stop short of the corner, then curve
/// through it with the corner itself as the control point. Doing the rounding by hand
/// rather than with `addArc(tangent1End:tangent2End:radius:)` keeps every point on the
/// path known, which is what stops the stray line stubs that appeared at the rim
/// corners when the two styles of arc were mixed.
///
/// `cornerRadius`/`notchCornerRadius` have no default any more — `DialView` always
/// passes both in, already multiplied by `deviceScale`, so a corner stays the same
/// proportion of the canopy on every screen instead of a fixed number of points.
private struct Fan: Shape {
    let halfAngle: Double
    var notchCenter: CGPoint
    var notchRadius: CGFloat
    /// Rounding where the rim meets a straight side.
    var cornerRadius: CGFloat
    /// Rounding where a straight side meets the curve around the hub. Smaller, because
    /// those two edges already meet at a shallow angle.
    var notchCornerRadius: CGFloat
    /// Drops the arc around the hub and leaves the path open, for stroking the canopy's
    /// own edge without also tracing around the refresh button — a separate element,
    /// not part of the canopy. Filling this would be wrong — it's only meant to be
    /// stroked.
    var isOutlineOnly = false
    /// Just the short connecting arc between the same two corners `outline` stops at —
    /// the piece that sits over the hub rather than under it. Its own separate flag,
    /// not a third state of `isOutlineOnly`, since both the rim-and-sides outline and
    /// this arc get stroked together (see `DialView.body`) rather than one replacing
    /// the other.
    var isTopArcOnly = false
    /// Replaces the curve around the hub notch with a straight chord between its two
    /// corners. Used for the canopy's inner shadow, which otherwise hugs that curve and
    /// leaves a faint shaded ring around the refresh button — exactly the "second
    /// circle outside the bezel" `outline` already avoids for the stroke.
    var stopsAtNotchCorners = false

    /// The same canopy, as an open edge that stops at the two bottom corners.
    var outline: Fan {
        var copy = self
        copy.isOutlineOnly = true
        return copy
    }

    /// Just the arc connecting those same two corners over the top of the hub.
    var topArc: Fan {
        var copy = self
        copy.isTopArcOnly = true
        return copy
    }

    var omittingHubCurve: Fan {
        var copy = self
        copy.stopsAtNotchCorners = true
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        // A point on the outer rim, in our own "0 = top, clockwise" convention.
        func rimPoint(_ degrees: Double) -> CGPoint {
            let radians = degrees * .pi / 180
            return CGPoint(x: center.x + radius * sin(radians), y: center.y - radius * cos(radians))
        }
        // Converts our "0 = top" convention to the atan2-style angle addArc expects.
        func standardAngle(_ ourDegrees: Double) -> Angle {
            Angle(degrees: ourDegrees - 90)
        }
        func notchPoint(_ radians: Double) -> CGPoint {
            CGPoint(x: notchCenter.x + notchRadius * cos(radians), y: notchCenter.y + notchRadius * sin(radians))
        }

        // The four corners: rim/side on each flank, and side/hub-curve below them.
        let rimRight = rimPoint(halfAngle)
        let rimLeft = rimPoint(-halfAngle)
        let notchRight = Self.lineCircleIntersection(from: rimRight, towards: center, circleCenter: notchCenter, radius: notchRadius)
        let notchLeft = Self.lineCircleIntersection(from: rimLeft, towards: center, circleCenter: notchCenter, radius: notchRadius)
        let notchRightAngle = Self.angle(of: notchRight, relativeTo: notchCenter)
        let notchLeftAngle = Self.angle(of: notchLeft, relativeTo: notchCenter)

        // How much of each arc the neighbouring corner eats, so the rounding takes the
        // same bite out of the curve as it does out of the straight side.
        let rimBite = Double(cornerRadius / radius) * 180 / .pi     // degrees
        let notchBite = Double(notchCornerRadius / notchRadius)      // radians

        var path = Path()

        if isOutlineOnly {
            // Left bottom corner, up the left side, across the rim, down the right side.
            path.move(to: notchPoint(notchLeftAngle + notchBite))
            path.addQuadCurve(to: Self.point(from: notchLeft, towards: rimLeft, distance: notchCornerRadius), control: notchLeft)
            path.addLine(to: Self.point(from: rimLeft, towards: notchLeft, distance: cornerRadius))
            path.addQuadCurve(to: rimPoint(-halfAngle + rimBite), control: rimLeft)
            path.addArc(
                center: center, radius: radius,
                startAngle: standardAngle(-halfAngle + rimBite),
                endAngle: standardAngle(halfAngle - rimBite),
                clockwise: false
            )
            path.addQuadCurve(to: Self.point(from: rimRight, towards: notchRight, distance: cornerRadius), control: rimRight)
            path.addLine(to: Self.point(from: notchRight, towards: rimRight, distance: notchCornerRadius))
            path.addQuadCurve(to: notchPoint(notchRightAngle - notchBite), control: notchRight)
            return path
        }

        if isTopArcOnly {
            // The short way between the same two corner points the rim-and-sides
            // outline stops at — through the canopy's interior, above the hub, rather
            // than the long way under it (that's the arc the *filled* canopy already
            // uses for its own bottom edge, reused as-is, not duplicated here).
            path.addArc(
                center: notchCenter, radius: notchRadius,
                startAngle: Angle(radians: notchRightAngle - notchBite),
                endAngle: Angle(radians: notchLeftAngle + notchBite),
                clockwise: true
            )
            return path
        }

        path.move(to: rimPoint(-halfAngle + rimBite))
        // The rim, from the left corner round to the right one.
        path.addArc(
            center: center, radius: radius,
            startAngle: standardAngle(-halfAngle + rimBite),
            endAngle: standardAngle(halfAngle - rimBite),
            clockwise: false
        )
        // Right rim corner, then down the straight side.
        path.addQuadCurve(to: Self.point(from: rimRight, towards: notchRight, distance: cornerRadius), control: rimRight)
        path.addLine(to: Self.point(from: notchRight, towards: rimRight, distance: notchCornerRadius))
        path.addQuadCurve(to: notchPoint(notchRightAngle - notchBite), control: notchRight)
        // The curve over the top of the refresh hub — or, when masking the inner
        // shadow, a straight chord across it instead, so the shading doesn't hug the
        // hub and show through as a ring around the button.
        if stopsAtNotchCorners {
            path.addLine(to: notchPoint(notchLeftAngle + notchBite))
        } else {
            path.addArc(
                center: notchCenter, radius: notchRadius,
                startAngle: Angle(radians: notchRightAngle - notchBite),
                endAngle: Angle(radians: notchLeftAngle + notchBite),
                clockwise: false
            )
        }
        // Out of the hub curve and back up the left straight side.
        path.addQuadCurve(to: Self.point(from: notchLeft, towards: rimLeft, distance: notchCornerRadius), control: notchLeft)
        path.addLine(to: Self.point(from: rimLeft, towards: notchLeft, distance: cornerRadius))
        path.addQuadCurve(to: rimPoint(-halfAngle + rimBite), control: rimLeft)
        path.closeSubpath()
        return path
    }

    /// The point `distance` along the way from `a` towards `b`.
    private static func point(from a: CGPoint, towards b: CGPoint, distance: CGFloat) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return a }
        return CGPoint(x: a.x + dx / length * distance, y: a.y + dy / length * distance)
    }

    /// Where segment `from -> towards` first crosses the given circle.
    private static func lineCircleIntersection(from a: CGPoint, towards b: CGPoint, circleCenter c: CGPoint, radius r: CGFloat) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let fx = a.x - c.x, fy = a.y - c.y
        let coefA = dx * dx + dy * dy
        let coefB = 2 * (fx * dx + fy * dy)
        let coefC = fx * fx + fy * fy - r * r
        let discriminant = coefB * coefB - 4 * coefA * coefC
        guard discriminant >= 0, coefA != 0 else { return b }
        let sqrtDiscriminant = discriminant.squareRoot()
        let candidates = [(-coefB - sqrtDiscriminant) / (2 * coefA), (-coefB + sqrtDiscriminant) / (2 * coefA)]
            .filter { $0 >= 0 && $0 <= 1 }
        let t = candidates.max() ?? 1
        return CGPoint(x: a.x + t * dx, y: a.y + t * dy)
    }

    private static func angle(of point: CGPoint, relativeTo center: CGPoint) -> Double {
        atan2(point.y - center.y, point.x - center.x)
    }
}

/// The refresh button's glyph, traced off the reference image: a thick ring with a bite
/// taken out of its upper right, and a right-angled chevron arrowhead standing in that
/// bite — apex pointing outwards at about 2 o'clock, one arm swept back over the ring's
/// top, the other reaching in towards the ring's centre.
///
/// Drawn by hand rather than borrowed from SF Symbols, because none of the stock
/// circular arrows match it: they all cap the arc with a solid triangular head, and the
/// one this replaced (`arrow.triangle.2.circlepath`) draws two arrows chasing each other
/// rather than a single one.
///
/// Every number below is a measurement taken off that reference in the reference's own
/// pixels, and the whole drawing is scaled uniformly into whatever rect it's handed — so
/// each constant can be checked back against the image instead of reading as an
/// unexplained decimal. This is an open path: stroke it, don't fill it.
struct RefreshGlyph: Shape {
    /// The artwork's bounds in those reference pixels: the ring's outer circle, plus the
    /// chevron's upper arm standing above it. The width is the ring's outer diameter,
    /// which is why the ring's centre lands on exactly half of it.
    private static let box = CGRect(x: 7.9, y: 4, width: 42.2, height: 54.3)

    private static let ringCenter = CGPoint(x: 29, y: 37.2)
    /// The middle of the stroke rather than its outer edge, since this path gets stroked
    /// rather than filled — the reference's ring runs from radius 13.9 to 21.1.
    private static let ringRadius: CGFloat = 17.5
    /// Where the ring stops either side of the bite. Measured the way SwiftUI measures,
    /// 0° at 3 o'clock and increasing clockwise, so the two are ordered start-then-end
    /// the long way round: the ~44° between them is the gap, not the arc.
    ///
    /// The reference cuts this end off flat at -7.4°; a round cap put half a stroke of
    /// bulge past that and closed the gap up too far, so the arc is started at 3 o'clock
    /// instead and the cap fills the difference.
    private static let ringStart = Angle.degrees(0)
    private static let ringEnd = Angle.degrees(315.7)

    /// The chevron. Its arms run at 45° either side of straight-out, which is what makes
    /// the head a right angle; the outward-facing one is the shorter of the two, and the
    /// inward one stops just short of the ring's centre.
    private static let apex = CGPoint(x: 46.4, y: 19)
    private static let upperArmTip = CGPoint(x: 35, y: 7.6)
    private static let innerArmTip = CGPoint(x: 33.2, y: 32.2)

    /// Taller than it is wide, because of that upper arm — callers sizing the glyph need
    /// this to avoid squashing it.
    static let aspectRatio = box.height / box.width

    /// Where the ring's centre falls within the glyph's frame. The spin animation has to
    /// turn about this rather than about the frame's middle: the arrowhead pushes the
    /// frame's centre well above the ring's, and spinning about it swings the whole ring
    /// round in a small circle instead of rotating it on the spot.
    static let ringCenterUnitPoint = UnitPoint(
        x: (ringCenter.x - box.minX) / box.width,
        y: (ringCenter.y - box.minY) / box.height
    )

    /// The stroke the reference is drawn with, ~17.5% of the ring's outer diameter — a
    /// good deal heavier than a `.semibold` SF Symbol at the same size. Measured off the
    /// reference where its luminance crosses halfway between glyph and face, rather than
    /// by counting fully-lit pixels, which undercounts by most of the soft edge.
    static func strokeWidth(forWidth width: CGFloat) -> CGFloat {
        width * 7.41 / box.width
    }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / Self.box.width, rect.height / Self.box.height)
        let originX = rect.midX - Self.box.midX * scale
        let originY = rect.midY - Self.box.midY * scale
        func place(_ point: CGPoint) -> CGPoint {
            CGPoint(x: originX + point.x * scale, y: originY + point.y * scale)
        }

        var path = Path()
        // `clockwise: false` sweeps in the direction of increasing angle, which reads as
        // clockwise on screen — the same convention `Fan` uses above.
        path.addArc(
            center: place(Self.ringCenter), radius: Self.ringRadius * scale,
            startAngle: Self.ringStart, endAngle: Self.ringEnd, clockwise: false
        )
        // A separate subpath, so the chevron isn't joined to the end of the arc by a
        // stray line across the gap.
        path.move(to: place(Self.upperArmTip))
        path.addLine(to: place(Self.apex))
        path.addLine(to: place(Self.innerArmTip))
        return path
    }
}

#Preview("Reading") {
    DialView(condition: .rain)
        .padding(.bottom, DialView.hubOverhang(scale: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
}

#Preview("No reading") {
    DialView(condition: nil)
        .padding(.bottom, DialView.hubOverhang(scale: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
}
