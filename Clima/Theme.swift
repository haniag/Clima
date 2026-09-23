//
//  Theme.swift
//  Clima
//

import SwiftUI
import UIKit

/// Every colour, type size and measurement the app uses, in one place.
///
/// The look follows Dieter Rams' Braun work: a warm neutral "paper and aluminium"
/// palette instead of pure black-on-white, exactly ONE saturated colour (reserved for
/// the pointer — it always means "this is the reading you want"), hairline rules rather
/// than drop shadows, and small tracked-out uppercase labels.
///
/// Light mode is the tuned one. The dark values below keep the app readable if the
/// Appearance switch is flipped, but they haven't had the same attention yet.
enum Theme {

    // MARK: - Responsive scale

    /// The screen this whole design was measured and tuned against: an iPhone 16 Pro,
    /// 402pt wide in portrait. Every fixed size elsewhere in the app is one of two
    /// things — a literal tuned for exactly this width, or a formula built from other
    /// tuned literals — so `deviceScale` (screen width ÷ this number) is the one factor
    /// that needs multiplying through to make the whole layout grow or shrink together
    /// on a different iPhone, rather than every element scaling independently.
    static let tunedScreenWidth: CGFloat = 402

    // MARK: - Palette

    /// The page itself.
    static let canvas = dynamic(light: 0xe8e9de, dark: 0x17171A)
    /// The dial's canopy. Lighter than the page, so the instrument reads as the one lit
    /// surface on screen.
    static let dialFace = dynamic(light: 0xf1f0e6, dark: 0x2A2A2E)
    /// The condition the pointer is sitting on.
    static let dialIconSelected = dynamic(light: 0x61616f, dark: 0xF0F0E6)
    /// Its two neighbours — present, but clearly not the reading.
    static let dialIconInactive = dynamic(light: 0xe3e2da, dark: 0x4A4A50)
    // The refresh button has no colours here: it's drawn from artwork in the asset
    // catalog (`refreshButton`, `refreshButtonPressed`), which carries its own.

    /// The panel behind the 7-day and hourly strips — and behind the settings drawer
    /// once it's open, so what the cover slides away from matches the strips above it.
    static let panel = dynamic(light: 0xd3d3ca, dark: 0x232327)
    /// The groove a slide-toggle's knob runs in. A step darker than `panel`, because
    /// the open drawer *is* a panel: when the track shared `panel`'s exact tone, shading
    /// alone was doing all the work, and it read as a slightly smudged patch of the
    /// surface rather than as a channel cut into it.
    static let toggleTrack = dynamic(light: 0xa8a7a2, dark: 0x141416)
    /// A slide-toggle knob's lit top face and its shaded underside — a warm-neutral pair
    /// in the same family as the rest of the palette. Filling the knob with the gradient
    /// between the two, rather than one flat near-white, is what makes it read as a
    /// raised slab catching light from above, the way a switch on a physical control
    /// panel does.
    static let toggleKnob = dynamic(light: 0xFAF9F4, dark: 0x4A4A46)
    static let toggleKnobShade = dynamic(light: 0xDFDED3, dark: 0x323230)
    /// Readings on a panel that carry the information: day letters, hours, highs.
    static let panelInk = dynamic(light: 0xffffff, dark: 0xF2F1ED)
    /// The quieter half of a panel: overnight lows and condition icons — the same
    /// darkened shade for both now, rather than two slightly different greys.
    static let panelInkMuted = dynamic(light: 0x8f8f87, dark: 0x6E6D6A)
    static let panelIcon = dynamic(light: 0x82828f, dark: 0x5E5D5A)

    /// The main temperature reading and the condition name underneath it — a single
    /// softer shade shared by both, rather than the sharper near-black `ink` used for
    /// page text like the header. One hex given, so (like the pointer/strip reds) it
    /// stays the same in dark mode rather than getting its own tuned dark value.
    static let readoutInk = dynamic(light: 0xb2b3b1, dark: 0x686669)

    /// Text on the page itself.
    static let ink = dynamic(light: 0x1A1A19, dark: 0xF2F1ED)
    /// Labels, and anything the eye should reach second.
    static let inkMuted = dynamic(light: 0x76736C, dark: 0x94918A)
    /// Outlines — structure that should be felt, not read.
    static let hairline = dynamic(light: 0xCBCCC1, dark: 0x3C3C39)
    /// The canopy's own outer trace — a touch darker than the shared `hairline` so the
    /// rim still reads as a drawn edge now that the canopy sits close to the screen
    /// edge, where it has less shadow around it to set it apart.
    ///
    /// Drawn in light mode only — dark alpha 0. On the dark page the canopy is already
    /// the lighter of the two surfaces, so its edge reads on tone alone; a pale line on
    /// top of that only made the dome look cut out and pasted onto the page.
    static let canopyOutline = dynamic(light: 0x919192, dark: 0x919192, darkAlpha: 0)
    /// The dial pointer's triangle tip. Red on the light page; in dark mode the pointer
    /// stops being a printed index mark and becomes the one lit thing on screen — the
    /// lamp casting `pointerBeam` — so it takes a warm sodium-yellow instead.
    ///
    /// That yellow is shared, verbatim, with the two swatches below it: in dark mode
    /// every index mark in the app — tip, shaft and the hourly strip's "now" marker — is
    /// one single value. The three stay separate constants only because light mode still
    /// draws its own distinctions between them.
    static let pointerTriangle = dynamic(light: 0xe35656, dark: 0xc7b348)
    /// The dial pointer's hairline shaft. On the light page it's a step duller than the
    /// triangle, so the tip still reads as the sharper, more precise end of the two. In
    /// dark mode that distinction is dropped: the beam does the work of separating tip
    /// from shaft there, brightest at the lamp and gone by the time the shaft picks up
    /// again below the icon.
    static let pointerLine = dynamic(light: 0xe35656, dark: 0xdbc650)
    /// The cone of light the pointer throws down the canopy in dark mode. A shade PALER
    /// than the lamp itself rather than the same value — light scatters toward white as
    /// it spreads, and the paler tone is what keeps the beam reading as light instead of
    /// as a wash of colour laid over the canopy.
    ///
    /// Fully transparent in light mode — light alpha 0 — since a beam only reads against
    /// a dark surface, and in daylight the pointer is just a mark printed on the dial.
    static let pointerBeam = dynamic(light: 0xC6C76A, dark: 0xC6C76A, lightAlpha: 0)
    /// The "now" marker on the hourly panel. It follows the dial pointer into dark mode
    /// — the same value, not merely a near one — so the app's one index mark keeps
    /// meaning the same thing, and looking the same, wherever it turns up.
    ///
    /// This swatch reads at face value now. The marker sits at the very top of its
    /// panel, right where that panel's `InnerShadow` is heaviest, and for as long as the
    /// shading was laid over the columns the mark eyedroppered around 28% darker than
    /// the value here — true of every colour this swatch has held, the original red
    /// included. `strip` now draws that shading behind the columns instead, which leaves
    /// the panel's edge untouched and lets the marker match the dial pointer. The value
    /// below is the one that was tuned under the old, darkening arrangement, so it will
    /// read brighter than before until it's retuned.
    static let stripIndicator = dynamic(light: 0xe86f6f, dark: 0xc7b451)

    // MARK: - Type

    /// Bariol ships only two weights (Light and Regular — no medium, semibold, bold or
    /// thin file exists), so every text style in the app maps onto one of those two,
    /// with SwiftUI's synthetic `.bold()` as the one extra step above Regular for the
    /// few spots that need to stand out further. Registered via the two .otf files in
    /// Fonts/ and the `UIAppFonts` build setting — no manual Xcode step needed, since
    /// the Clima folder is a synchronized group that picks up new files on its own.
    fileprivate static let lightFontName = "Bariol-Light"
    fileprivate static let regularFontName = "Bariol-Regular"

    /// The big temperature. Bariol's one light weight stands in for the system font's
    /// `.thin`. `.monospacedDigit()` is left in place for when the reading changes, but
    /// Bariol has no monospaced-digit feature to actually honour it — each digit keeps
    /// its own natural width, so the number may shift slightly rather than holding
    /// perfectly still the way the system font did.
    ///
    /// A `Font` value can't be resized after the fact the way a plain number can, so
    /// unlike most of this file's measurements, the three text styles below have to be
    /// functions that take the scale directly rather than pre-built constants.
    static func readoutFont(scale: CGFloat) -> Font {
        Font.custom(lightFontName, size: 62 * scale).monospacedDigit()
    }
    /// A reading in the forecast strips.
    static func valueFont(scale: CGFloat) -> Font {
        Font.custom(regularFontName, size: 15 * scale).monospacedDigit()
    }
    /// A reading that should carry more weight — a daily high, the current hour.
    /// Synthetic bold on top of Regular, since there's no true medium/semibold face to
    /// reach for — without it, this would render identically to `valueFont` and the
    /// "today"/"now" emphasis those two fonts exist to carry would disappear entirely.
    static func valueStrongFont(scale: CGFloat) -> Font {
        Font.custom(regularFontName, size: 15 * scale).bold().monospacedDigit()
    }

    // MARK: - Measurements

    /// Page margin. Everything on screen lines up to these two edges. The tuned value
    /// at `deviceScale` 1 — multiply by scale at the point of use, the same as every
    /// other measurement in this section.
    static let gutter: CGFloat = 24
    /// Vertical gap between the major blocks of the screen.
    static let blockGap: CGFloat = 26
}

// MARK: - Responsive scale

private struct DeviceScaleKey: EnvironmentKey {
    // Defaults to the tuned size (no scaling) so a preview or anywhere else that isn't
    // sitting under the root's GeometryReader still renders at the exact measurements
    // this design was built against, rather than silently shrinking to zero.
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// How much bigger or smaller this screen is than the iPhone 16 Pro (`Theme.
    /// tunedScreenWidth`) the app was designed on: 1 on that device, a little under 1 on
    /// the smallest iOS 18 iPhones (SE, mini — 375pt wide), a little over 1 on the
    /// largest (16 Pro Max — 440pt). Set once, from the actual measured screen width, by
    /// the GeometryReader wrapping the root view in `ClimaApp`; every other view just
    /// reads it back with `@Environment(\.deviceScale)`.
    var deviceScale: CGFloat {
        get { self[DeviceScaleKey.self] }
        set { self[DeviceScaleKey.self] = newValue }
    }

}

// MARK: - Helpers

private struct ClimaCapsModifier: ViewModifier {
    @Environment(\.deviceScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let tracking: CGFloat

    func body(content: Content) -> some View {
        // Every caller passes .bold, .medium, or the .semibold default — never
        // .light/.thin — so the only real branch Bariol's two weights need to make
        // here is "the one spot that asked for .bold" versus "everything else".
        let base = Font.custom(Theme.regularFontName, size: size * scale)
        return content
            .font(weight == .bold ? base.bold() : base)
            .textCase(.uppercase)
            .tracking(tracking * scale)
    }
}

extension View {
    /// The Braun product label: small, uppercase, tracked out, quiet. Used for every
    /// caption, column heading and control label in the app, so they all read as one
    /// family of labels rather than as shrunken body text.
    ///
    /// Reads `deviceScale` itself (via the modifier above) rather than taking it as a
    /// parameter, so every one of this helper's many call sites across the app stayed
    /// untouched when scaling was added — only the definition needed to change.
    func climaCaps(size: CGFloat = 11, weight: Font.Weight = .semibold, tracking: CGFloat = 1.6) -> some View {
        modifier(ClimaCapsModifier(size: size, weight: weight, tracking: tracking))
    }
}

/// A ~5pt shadow hugging the inside of a shape's edge: a blurred stroke of the shape's
/// own outline, nudged downward and then masked back to the shape, so only the shaded
/// sliver near the edge shows rather than a broad wash.
///
/// Shared by the dial canopy, the two forecast panels and the slide-toggles' channels,
/// so every moulded surface in the app is lit by the same imaginary light.
struct InnerShadow<S: Shape>: View {
    let shape: S
    var opacity: Double = 0.35
    /// How far in from the edge the shading reaches. The default suits the big surfaces
    /// this started out on; anything small needs less, or the shadow simply floods it —
    /// on a 28pt toggle channel the default reached most of the way across and read as
    /// a smear rather than as a groove with a lip. Blur and offset are derived from it
    /// rather than set separately, so a caller has one number to think about and the
    /// shape of the shadow stays the same at every size.
    var spread: CGFloat = 9
    var scale: CGFloat = 1

    private var softness: CGFloat { spread * 0.39 * scale }

    var body: some View {
        shape
            .stroke(Color.black.opacity(opacity), lineWidth: spread * scale)
            .blur(radius: softness)
            .offset(y: softness)
            .mask(shape)
            .allowsHitTesting(false)
    }
}

/// The knurling on a physical control: a row of fine vertical grooves, each drawn as a
/// dark line with a lit edge immediately to its right, so it reads as cut into the
/// surface rather than painted onto it. (Light from the top-left, matching the bevel on
/// the toggle knobs; a groove lit from there has its right-hand wall in the light and
/// its left-hand wall in shadow.)
///
/// Vertical because everything wearing this texture slides sideways — the settings
/// drawer's cover and the slide-toggle knobs — and ridges bite best across the
/// direction of travel. One shape for both, so "put your finger here" looks the same
/// wherever the app says it.
struct GripRidges: View {
    var count: Int = 3
    /// How tall each groove is. Left to the caller rather than derived, since the same
    /// texture has to suit a 22pt knob face and a 56pt drawer cover.
    var height: CGFloat
    /// Scales both lines' strength together, for surfaces too pale to take them at full
    /// contrast.
    var strength: Double = 1
    /// Gap between grooves. Tighter on small faces, where too much air between them
    /// stops them reading as one knurled patch.
    var spacing: CGFloat = 3
    var scale: CGFloat = 1

    /// How wide a patch these settings make, for callers that need to place it by its
    /// centre rather than against an edge. Derived from the same numbers `body` lays
    /// out with, so the two can't drift apart.
    static func width(count: Int = 3, spacing: CGFloat = 3, scale: CGFloat = 1) -> CGFloat {
        (CGFloat(count) * 2 + CGFloat(count - 1) * spacing) * scale
    }

    var body: some View {
        HStack(spacing: spacing * scale) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 0) {
                    Rectangle().fill(Color.black.opacity(0.22 * strength))
                    Rectangle().fill(Color.white.opacity(0.55 * strength))
                }
                .frame(width: 2 * scale)
            }
        }
        .frame(height: height)
        // Texture only: it must never eat the tap meant for the control underneath it.
        .allowsHitTesting(false)
    }
}

/// An upward-pointing triangle — the tip of the dial's pointer, and of the smaller
/// "now" markers on the forecast strips, so the same shape means the same thing
/// everywhere in the app.
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Formatting

/// Formats a Fahrenheit reading, converting to Celsius when the switch is on.
///
/// Only the degree sign is shown, never the unit: the unit is already stated once, by
/// the °F/°C switch in Settings. Repeating it on all 22 readings on screen is noise,
/// not information.
///
/// `nil` — no reading, for whatever reason — formats as a bare dash, with no degree sign
/// after it: a unit with nothing to qualify reads as a stray mark rather than as a
/// deliberate blank. Taking an optional here rather than making each caller unwrap is
/// what keeps that decision in one place, so every temperature on screen goes missing
/// the same way.
func temperatureText(_ fahrenheit: Int?, useCelsius: Bool) -> String {
    guard let fahrenheit else { return "—" }
    guard useCelsius else { return "\(fahrenheit)°" }
    let celsius = Int((Double(fahrenheit - 32) * 5 / 9).rounded())
    return "\(celsius)°"
}

// MARK: - Private

private extension Theme {
    /// Builds a colour that resolves differently in light and dark mode from two hex
    /// values, so the rest of the file can just read as a list of paired swatches.
    ///
    /// The two alphas are for the handful of details that belong to only one of the two
    /// modes: an alpha of 0 is how a swatch says "draw nothing at all here", which keeps
    /// that decision in this file alongside the rest of the palette rather than
    /// scattering `if colorScheme == .dark` through the views.
    static func dynamic(
        light: UInt32,
        dark: UInt32,
        lightAlpha: CGFloat = 1,
        darkAlpha: CGFloat = 1
    ) -> Color {
        Color(UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            return UIColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
