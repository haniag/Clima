//
//  SettingsDrawer.swift
//  Clima
//
//  The settings bar at the bottom of the screen. Moved out of WeatherDialScreen.swift, unchanged.
//

import SwiftUI

// MARK: - Settings drawer

/// The two switches, kept behind a plain rectangular cover that slides out of the way.
///
/// The knurling near the cover's right end is the finger grip, and the only thing on
/// the closed row that invites a touch. Touching it slides the cover left; it stops
/// with just that grip still showing at the left end, so the same texture that opened
/// the drawer is what's under the finger to close it again.
///
/// The cover doesn't fill the row — it sits in it with `gap` of clearance on every
/// side, and the recess showing through that clearance is what draws the seam around
/// it. A real gap rather than a line stroked onto the cover, because a stroke only
/// exists where the cover does: slid open, its left end is cut off by the clip, and a
/// stroked outline would leave the parked grip with a seam on three sides and a raw
/// edge on the fourth.
///
/// The switches don't move between the two states — they sit permanently inset past
/// where the parked grip ends, and the cover slides over them — so nothing jumps
/// sideways as the drawer opens.
struct SettingsDrawer: View {
    @Binding var useCelsius: Bool
    @Binding var isDarkMode: Bool

    @Environment(\.deviceScale) private var deviceScale
    @State private var isOpen = false

    /// Static as well as an instance property, because the page above reserves exactly
    /// this much room to scroll behind, and the two mustn't drift apart.
    static func height(scale: CGFloat) -> CGFloat { 56 * scale }

    /// How far the bar floats above the screen's physical bottom edge.
    ///
    /// This is what keeps the corners honest. Run flush to the edge, the display's own
    /// ~55-62pt corner curve cuts across the bar's 18pt corners and swallows the 3pt seam
    /// entirely at both ends — the screen's bottom is not a rectangle, and there's no
    /// public API for its radius to match against. Held `gutter` clear of that edge and
    /// the same distance in from the sides as the forecast panels, the bar's corners stay
    /// well inside the curve on every iPhone, and the seam reads evenly the whole way
    /// round in both states.
    static func bottomMargin(scale: CGFloat) -> CGFloat { Theme.gutter * scale }

    /// The forecast panels' width, so the bar lines up with them and with the canopy.
    private var width: CGFloat { DialView.canopyWidth(scale: deviceScale) }
    private var height: CGFloat { Self.height(scale: deviceScale) }
    /// How much cover stays on screen once it's open: enough to hold the whole knurled
    /// grip, and with it the way back.
    ///
    /// Back to 44 now that the bar is its tuned height again — it was only widened to 60
    /// to keep the parked block from reading as a tall thin tab when the bar stretched
    /// down to the screen's edge, and that's no longer the shape it has to balance.
    private var gripWidth: CGFloat { 44 * deviceScale }
    /// The clearance between the cover and the recess it rides in, on all four sides.
    private var gap: CGFloat { 3 * deviceScale }
    /// Concentric with the slot's rather than a value of its own: exactly one `gap`
    /// smaller, so the seam between cover and recess holds the same width round the
    /// corners as it does along the straight edges. At the old flat 10 against the slot's
    /// 18 the two curves weren't concentric, and the seam quietly fattened at all four.
    private var coverRadius: CGFloat { baseStripCornerRadius * deviceScale - gap }

    /// The cover is the row less its clearance, so `travel` — and the grip left behind
    /// at the end of it — are both measured against the cover's own width.
    private var coverWidth: CGFloat { width - 2 * gap }
    private var coverHeight: CGFloat { height - 2 * gap }
    private var travel: CGFloat { coverWidth - gripWidth }

    private var coverShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
    }

    private var ridgesWidth: CGFloat { GripRidges.width(scale: deviceScale) }

    /// The drawer's outline — the forecast panels' shape, to the point of sharing their
    /// corner radius. Rounded on all four corners again now that the bar floats clear of
    /// the screen's edge and has four corners of its own to show.
    private var slotShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: baseStripCornerRadius * deviceScale, style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Background, rounding and shading applied in the same order `strip` uses,
            // so what the cover slides off to reveal is indistinguishable from one of
            // the forecast panels above it — shadow falling across the switches
            // included, exactly as it falls across the forecast columns.
            switches
                // Faded rather than merely covered, so a switch can't show through the
                // clearance around the cover while the drawer is shut. The opacity sits
                // above the background deliberately: the recess itself stays visible in
                // both states, and it's what fills the seam around the cover.
                .opacity(isOpen ? 1 : 0)
                .allowsHitTesting(isOpen)
                .frame(width: width, height: height)
                .background(Theme.panel)
                .clipShape(slotShape)
                .overlay(InnerShadow(shape: slotShape, scale: deviceScale))

            coverLayer
        }
        .frame(width: width, height: height)
    }

    /// The cover, and the window it slides within.
    ///
    /// `offset` moves the cover without moving the frame around it, so the clip cuts it
    /// at that frame's edge — and since `padding` holds the frame `gap` in from the row,
    /// the open state keeps its clearance on the left exactly as the closed state has it
    /// on the right.
    ///
    /// The clip is `coverShape`, not a plain rectangle. A rectangular one left the parked
    /// grip with two square corners at its cut end, and those sat outside the recess's own
    /// rounded corner — the cover visibly spilled out of the slot it's supposed to ride
    /// in. Clipping to the same rounded shape trims the parked end to the recess's curve
    /// instead, and costs nothing when the drawer is shut, since the cover is that shape
    /// already.
    private var coverLayer: some View {
        cover
            .offset(x: isOpen ? -travel : 0)
            .frame(width: coverWidth, height: coverHeight, alignment: .leading)
            .clipShape(coverShape)
            .padding(gap)
    }

    private var switches: some View {
        HStack {
            SlideToggle(leading: "°F", trailing: "°C", tracked: false, isTrailing: $useCelsius)
            Spacer()
            SlideToggle(leading: "Light", trailing: "Dark", isTrailing: $isDarkMode)
        }
        // Clear of where the parked cover ends — its own `gap` inset included, since
        // the switches are measured from the row's edge and the cover isn't.
        .padding(.leading, gap + gripWidth + 10 * deviceScale)
        // The row reaches the screen's own edge now, so the last label needs a real
        // margin rather than just enough to clear a rounded corner.
        .padding(.trailing, 20 * deviceScale)
    }

    private var cover: some View {
        coverShape
            // Page colour, not a surface tone: closed, the cover is meant to sit flush
            // and near-invisible, leaving only the seam around it and the knurling to
            // say there's anything here at all.
            .fill(Theme.canvas)
            .frame(width: coverWidth, height: coverHeight)
            // The knurling — the same texture the toggle knobs wear, and now the only
            // thing marking the grip. Centred in the width that stays on screen when
            // the drawer is open, so the finger lands on it in both states. Held at
            // reduced strength because the cover is page colour, pale enough that
            // full-contrast lines would read as a printed barcode rather than a
            // texture.
            .overlay(alignment: .trailing) {
                GripRidges(height: 18 * deviceScale, strength: 0.85, scale: deviceScale)
                    .padding(.trailing, (gripWidth - ridgesWidth) / 2)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    isOpen.toggle()
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isOpen ? "Hide settings" : "Show settings")
    }
}
