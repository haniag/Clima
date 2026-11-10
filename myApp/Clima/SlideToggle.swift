//
//  SlideToggle.swift
//  Clima
//
//  The slide switch the settings bar uses. Moved out of WeatherDialScreen.swift, unchanged.
//

import SwiftUI

// MARK: - Controls

/// A two-position slide switch, built to look like the hardware kind: a channel milled
/// into the panel, and a raised, knurled slab riding in it between two engraved detent
/// marks.
///
/// Four things do the work, all of them lit from above like the rest of the app's
/// moulded surfaces (`InnerShadow`):
/// - The channel is its own tone (`Theme.toggleTrack`), darker than the panel it's cut
///   into, and squared off rather than a capsule. A capsule of the panel's own colour
///   reads as a pill drawn on the surface; a darker rounded rectangle reads as a hole
///   in it.
/// - The knob is a slab, not a disc — filled with a top-to-bottom gradient and rimmed
///   with a bright top edge falling to a dark bottom one, so it has a visible thickness
///   standing proud of the channel.
/// - It carries `GripRidges`, the same knurling as the drawer's cover. This is the part
///   that says *this* is the bit to push, rather than leaving a smooth lozenge that
///   could as easily be a progress indicator.
/// - A tick beside each end marks where the knob stops, and brightens with the label on
///   the side it's resting against — the detent marks on the reference panel.
///
/// The words ("°F"/"°C", "Light"/"Dark") stay outside the channel rather than being
/// printed on the knob, which is how a panel switch is labelled and also what lets the
/// label itself be a tap target.
struct SlideToggle: View {
    let leading: String
    let trailing: String
    /// Word labels want the tracked-out treatment the rest of the app uses; a unit like
    /// "°F" does not — spacing it out reads as "° F".
    var tracked = true
    @Binding var isTrailing: Bool

    @Environment(\.deviceScale) private var deviceScale

    /// Wider than it is tall, along the direction of travel: the proportion of a thumb
    /// slide rather than of a button.
    private var knobWidth: CGFloat { 28 * deviceScale }
    private var knobHeight: CGFloat { 22 * deviceScale }
    /// The gap between knob and channel wall. Small — a machined fit, not a loose one.
    private var padding: CGFloat { 3 * deviceScale }
    private var trackHeight: CGFloat { knobHeight + 2 * padding }
    /// How far the knob throws. A shade under its own width: plenty for the two
    /// positions to be unmistakable at a glance, and no more — this row carries two
    /// switches and four labels, and a longer channel pushes "DARK" off the panel's
    /// right edge, where the drawer's clip cuts it in half.
    private var travel: CGFloat { 22 * deviceScale }
    private var trackWidth: CGFloat { knobWidth + travel + 2 * padding }

    /// Rounded, but well short of a capsule — the channel should keep its corners.
    private var trackShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8 * deviceScale, style: .continuous)
    }
    /// A touch tighter than the channel's, so the knob looks like a part machined to
    /// drop into it rather than a shape scaled down from it.
    private var knobShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 6 * deviceScale, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 4 * deviceScale) {
            label(leading, isSelected: !isTrailing) { isTrailing = false }
            tick(isSelected: !isTrailing)
            track
            tick(isSelected: isTrailing)
            label(trailing, isSelected: isTrailing) { isTrailing = true }
        }
        // The switch's detent, felt: one tick whenever it changes sides, whether by a tap
        // on the channel or on a label.
        .sensoryFeedback(.selection, trigger: isTrailing)
    }

    private func label(_ title: String, isSelected: Bool, select: @escaping () -> Void) -> some View {
        Text(title)
            .climaCaps(.small, tracked: tracked)
            .foregroundStyle(isSelected ? Theme.ink : Theme.inkMuted)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { select() } }
    }

    /// The detent mark between a label and the end of the channel. Deliberately faint
    /// when it isn't the live one: two marks of equal weight would read as decoration,
    /// where one bright and one dim reads as a position indicator.
    private func tick(isSelected: Bool) -> some View {
        Capsule()
            .fill(isSelected ? Theme.ink : Theme.inkMuted.opacity(0.4))
            .frame(width: 4 * deviceScale, height: deviceScale)
    }

    private var track: some View {
        trackShape
            .fill(Theme.toggleTrack)
            .frame(width: trackWidth, height: trackHeight)
            // Colour alone only makes it a dark shape; the shading is what gives the
            // channel a lip and a floor, and so a depth. Tightened well in from the
            // default `spread`, which is sized for the forecast panels — at full width
            // it washes across a channel this narrow instead of hugging its edge.
            .overlay(InnerShadow(shape: trackShape, opacity: 0.3, spread: 5, scale: deviceScale))
            .overlay(alignment: isTrailing ? .trailing : .leading) {
                knob.padding(padding)
            }
            .contentShape(trackShape)
            .onTapGesture {
                SoundPlayer.shared.play(.toggle)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isTrailing.toggle() }
            }
    }

    /// The raised knob: a top-lit gradient face carrying the grip knurling, a bevel
    /// stroked round the rim (bright at the top, dark at the bottom) to give it an
    /// edge, and a drop shadow cast down into the channel so it sits *above* the panel
    /// rather than flush in it.
    private var knob: some View {
        knobShape
            .fill(
                LinearGradient(
                    colors: [Theme.toggleKnob, Theme.toggleKnobShade],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: knobWidth, height: knobHeight)
            // Well short of the knob's full height, and tighter together than the
            // drawer cover's: the grooves have to read as one patch of knurling on a
            // face this small, where at full spacing and height they separate into
            // three bars and start looking like an icon.
            .overlay(GripRidges(height: knobHeight * 0.38, spacing: 2.5, scale: deviceScale))
            .overlay(
                knobShape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.9), .white.opacity(0.06), .black.opacity(0.2)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: deviceScale
                )
            )
            // Straight down, not down-and-right: everything else on the page is lit from
            // directly above, and an offset shadow here would light this one control
            // from a different sun.
            .shadow(color: .black.opacity(0.3), radius: 2 * deviceScale, y: 1.5 * deviceScale)
    }
}
