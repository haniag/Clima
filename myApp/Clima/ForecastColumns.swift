//
//  ForecastColumns.swift
//  Clima
//
//  The columns of the two forecast strips. Moved out of WeatherDialScreen.swift, unchanged.
//

import SwiftUI

// MARK: - Forecast columns

/// The width every value's icon and "now" marker are sized to, at `deviceScale` 1 (the
/// iPhone 16 Pro this was tuned on).
///
/// Measured from the rendered app rather than guessed: the temperature text is ~24pt
/// wide at its font, but the condition icons — measured the same way, glyph edge to
/// glyph edge — only fill about half of their old 26pt frame, so *nominally* matching
/// the number's width left them looking much smaller than it. 41pt is about as far as
/// that can be pushed before it outgrows what's actually available: the hourly strip's
/// 8 columns leave ~41.5pt each inside the panel, the tightest of the two rows, so this
/// is at the ceiling rather than a true pixel match to the number. Scaling this
/// alongside the panel it sits in keeps that same tight-but-fitting relationship on
/// every iPhone rather than just the one it was measured on.
let baseStripContentWidth: CGFloat = 41

/// The corner radius of a forecast panel, at `deviceScale` 1. Shared with the settings
/// drawer, whose open state is meant to be indistinguishable from one of these panels —
/// one number, so the two can't drift apart.
let baseStripCornerRadius: CGFloat = 18

/// One column in the 7-day strip: weekday name, condition icon, high, low, and the
/// chance of precipitation.
struct ForecastDayColumn: View {
    let day: DailyForecast
    /// Whether this column carries the marker: the day the hourly strip above is
    /// showing — see `markedDay`. Today, until the hours are swiped into another day.
    let isMarked: Bool
    /// Called when the column is tapped: swipes the hourly strip to this day.
    let onSelect: () -> Void

    @AppStorage("useCelsius") private var useCelsius = TemperatureUnit.phoneUsesCelsius
    @Environment(\.deviceScale) private var deviceScale
    /// The place the weather is for — see `WeatherDialScreen.timeZone`.
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        column
            // The whole column is the target, gaps between its rows included.
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Shows this day's hours")
    }

    private var column: some View {
        StripColumn(isActive: isMarked) {
            Text(day.dayLabel(in: timeZone))
                .climaCaps(.heading)
                .foregroundStyle(Theme.panelInk)

            // No condition, no icon — a guessed one would be as misleading as a guessed
            // number. The empty frame keeps every column's rows on the same baselines, so
            // the strip doesn't jump when a reading finally lands.
            Group {
                if let condition = day.condition {
                    Image(condition.iconName)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Theme.panelIcon)
                } else {
                    Color.clear
                }
            }
            .frame(width: baseStripContentWidth * deviceScale, height: baseStripContentWidth * deviceScale)

            // Regular even for today: the marker above the column already says which day
            // is today, and a bold high read as heavier than the rest of the row.
            Text(temperatureText(day.highTemp, useCelsius: useCelsius))
                .font(Theme.valueFont(scale: deviceScale))
                .foregroundStyle(Theme.panelInk)

            Text(temperatureText(day.lowTemp, useCelsius: useCelsius))
                .font(Theme.valueFont(scale: deviceScale))
                .foregroundStyle(Theme.panelInkMuted)

            // The condition icon above already says what's coming, so the number needs
            // no drop icon beside it.
            Text(precipitationChanceText(day.precipitationChance))
                .font(Theme.valueFont(scale: deviceScale))
                .foregroundStyle(Theme.panelInkMuted)
        }
    }
}

/// The chance as the weather service reports it ("0%", "75%"), on both strips, or "—"
/// when there's no reading yet.
func precipitationChanceText(_ chance: Int?) -> String {
    guard let chance else {
        return "—"
    }
    return "\(chance)%"
}

/// One column in the hourly strip: the hour, condition icon, temperature, and the
/// chance of precipitation.
struct HourlyColumn: View {
    let hour: HourlyForecast

    @AppStorage("useCelsius") private var useCelsius = TemperatureUnit.phoneUsesCelsius
    @Environment(\.deviceScale) private var deviceScale
    /// The place the weather is for — see `WeatherDialScreen.timeZone`.
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        // Never active: the hourly strip's marker is pinned to the panel, not carried by
        // a column — see `hourlyStrip`. The column still keeps the marker's slot clear.
        StripColumn(isActive: false) {
            // Midnight is "00" like any other hour; the 7-day strip's marker is what
            // says which day the strip has reached.
            Text(hour.timeLabel(in: timeZone))
                .climaCaps(.heading)
                .foregroundStyle(Theme.panelInk)

            // Same as the 7-day column: no condition means no icon, but the frame stays
            // so the hours keep their rows aligned.
            Group {
                if let condition = hour.condition {
                    Image(condition.iconName)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Theme.panelIcon)
                } else {
                    Color.clear
                }
            }
            .frame(width: baseStripContentWidth * deviceScale, height: baseStripContentWidth * deviceScale)

            Text(temperatureText(hour.temperature, useCelsius: useCelsius))
                .font(Theme.valueFont(scale: deviceScale))
                .foregroundStyle(Theme.panelInk)

            Text(precipitationChanceText(hour.precipitationChance))
                .font(Theme.valueFont(scale: deviceScale))
                .foregroundStyle(Theme.panelInkMuted)
        }
    }
}

/// One column on the hourly strip: an hour, or a sunrise or sunset between two of them.
enum HourlyStripItem: Identifiable {
    case hour(HourlyForecast)
    case sun(SunEvent)

    /// What the strip's scroll position is kept in. Built from the hour's start or the
    /// event itself rather than `HourlyForecast.id`, because every reading makes new ids
    /// and the scroll position has to survive from one to the next.
    enum ID: Hashable {
        case hour(Date)
        case sun(SunEvent)

        /// When the column is: the hour's start, or the event's moment.
        var date: Date {
            switch self {
            case .hour(let date): date
            case .sun(let event): event.date
            }
        }
    }

    var id: ID {
        switch self {
        case .hour(let hour): .hour(hour.date)
        case .sun(let event): .sun(event)
        }
    }

    /// Orders the columns by time. A sunrise or sunset at exactly the top of an hour
    /// goes after that hour's column, the same as one a minute later would.
    var sortKey: (Date, Int) {
        switch self {
        case .hour(let hour): (hour.date, 0)
        case .sun(let event): (event.date, 1)
        }
    }
}

/// A sunrise or sunset column on the hourly strip: the time it happens, to the minute,
/// over its icon. The temperature and rain-chance rows are left empty — there's no
/// forecast for a moment, only for an hour.
struct SunEventColumn: View {
    let event: SunEvent

    @Environment(\.deviceScale) private var deviceScale
    /// The place the weather is for — see `WeatherDialScreen.timeZone`.
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        // Never active, the same as `HourlyColumn`.
        StripColumn(isActive: false) {
            Text(event.timeLabel(in: timeZone))
                .climaCaps(.heading)
                .foregroundStyle(Theme.panelInk)

            // The artwork fills nearly its whole canvas, where the condition icons only
            // fill about half of theirs (see `baseStripContentWidth`), so it's drawn at a
            // bit over half the frame to come out the same size as its neighbours. The
            // outer frame matches theirs so the rows below stay on the same baselines.
            Image(event.iconName)
                .resizable()
                .scaledToFit()
                .frame(width: baseStripContentWidth * 0.55 * deviceScale)
                .frame(width: baseStripContentWidth * deviceScale, height: baseStripContentWidth * deviceScale)

            // Held open but not shown, so the column is as tall as the hours either side.
            Text("—")
                .font(Theme.valueFont(scale: deviceScale))
                .hidden()
            Text("—")
                .font(Theme.valueFont(scale: deviceScale))
                .hidden()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.accessibilityLabel(in: timeZone))
    }
}

/// The shared shell for both strips: an equal-width column topped by the "now" marker,
/// which is always laid out but only visible on the active column, so every column in a
/// row keeps its contents on the same baselines.

struct StripColumn<Content: View>: View {
    let isActive: Bool
    @ViewBuilder let content: Content

    @Environment(\.deviceScale) private var deviceScale

    var body: some View {
        VStack(spacing: 0) {
            StripMarker()
                .opacity(isActive ? 1 : 0)
                // A quick cross-fade when the marker moves — on the 7-day strip it follows
                // the hourly strip's swiping from one day to the next.
                .animation(.easeInOut(duration: 0.2), value: isActive)

            VStack(spacing: 7 * deviceScale) {
                content
            }
            // Measured from the marker's slot, so the triangle's tip still clears the
            // heading beneath it.
            .padding(.top, 6 * deviceScale)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The "now" marker on its own: the same triangle-and-line index mark the dial's pointer
/// uses, shrunk down — one shape, one colour, one meaning throughout the app. The 7-day
/// strip's columns each carry one, shown on the marked day; the hourly strip has a single
/// one pinned over its first slot, with the hours sliding underneath.
struct StripMarker: View {
    @Environment(\.deviceScale) private var deviceScale

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.indexMark)
                .frame(width: baseStripContentWidth * deviceScale, height: 4 * deviceScale)

            Triangle()
                .fill(Theme.indexMark)
                .frame(width: 16 * deviceScale, height: 7 * deviceScale)
        }
    }
}
