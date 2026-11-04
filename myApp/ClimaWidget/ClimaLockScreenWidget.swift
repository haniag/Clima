//
//  ClimaLockScreenWidget.swift
//  ClimaWidget
//

import SwiftUI
import WidgetKit

/// The lock screen widget: today's temperature on an arc running from today's low to
/// today's high, and the next three hours beside it.
///
/// Rectangular only — the one lock screen size wide enough for both halves.
@main
struct ClimaLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetWeather.widgetKind, provider: WeatherTimelineProvider()) { entry in
            LockScreenWeatherView(entry: entry)
        }
        .configurationDisplayName("Clima")
        .description("Today's temperature and the next few hours.")
        .supportedFamilies([.accessoryRectangular])
    }
}

/// What the widget shows at one moment.
///
/// `nonisolated` here and below because this target, like the app, puts code on the
/// main actor by default, and WidgetKit asks for timelines from off it.
nonisolated struct WeatherEntry: TimelineEntry {
    let date: Date
    /// Nil when there's nothing to show: the app hasn't saved a reading yet, or the
    /// forecast it saved has run out.
    let reading: Reading?

    struct Reading {
        /// Degrees Fahrenheit, now.
        let temperature: Int
        /// Today's low and high, °F, or nil if the forecast didn't have them.
        let low: Int?
        let high: Int?
        /// Up to three hours after this one.
        let nextHours: [WidgetWeather.Hour]
        let timeZone: TimeZone
        let useCelsius: Bool
    }
}

/// Builds the widget's timeline: a fresh fetch of its own if one succeeds, otherwise
/// the reading last saved by the app or by an earlier fetch.
///
/// One entry now, then one at the top of each following hour, each worked out from the
/// forecast — so if the next fetch is late or fails, the widget still moves forward for
/// as long as the forecast reaches. A fetch in the app replaces the whole timeline
/// straight away (see `WidgetWeather.publish`).
nonisolated struct WeatherTimelineProvider: TimelineProvider {
    /// How many hours ahead one timeline covers.
    private static let hoursAhead = 24

    /// How long until WidgetKit is asked for the next timeline, and so the next fetch.
    ///
    /// iOS gives each widget a daily budget of reloads — roughly 40 to 70 — and a
    /// half-hourly one stays inside it. Asking for more often doesn't get more often;
    /// iOS just starts delaying them.
    private static let refreshInterval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: .now, reading: WidgetWeather.preview.reading(at: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
        // The widget gallery shows a made-up reading until the app has saved a real one,
        // so the preview there isn't an empty "open Clima" box.
        let weather = WidgetWeather.saved ?? (context.isPreview ? .preview : nil)
        completion(WeatherEntry(date: .now, reading: weather?.reading(at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
        Task { @MainActor in
            let weather = await WidgetFetcher.refreshed() ?? WidgetWeather.saved
            completion(Self.timeline(for: weather, at: Date()))
        }
    }

    private static func timeline(for weather: WidgetWeather?, at now: Date) -> Timeline<WeatherEntry> {
        let nextRefresh = TimelineReloadPolicy.after(now.addingTimeInterval(refreshInterval))
        guard let weather else {
            // Nothing to count forward from — try again at the next refresh.
            return Timeline(entries: [WeatherEntry(date: now, reading: nil)], policy: nextRefresh)
        }

        var calendar = Calendar.current
        calendar.timeZone = weather.timeZone
        let thisHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let hourStarts = (1...Self.hoursAhead).compactMap {
            calendar.date(byAdding: .hour, value: $0, to: thisHour)
        }

        let entries = ([now] + hourStarts).map { WeatherEntry(date: $0, reading: weather.reading(at: $0)) }
        return Timeline(entries: entries, policy: nextRefresh)
    }
}

nonisolated extension WidgetWeather {
    /// What the widget shows at `date`, or nil once the saved forecast doesn't reach it.
    ///
    /// The temperature is the one measured at the fetch while it's still that hour, and
    /// the hourly forecast's after that — the hours start at the one after the fetch, so
    /// there's never a gap between the two.
    func reading(at date: Date) -> WeatherEntry.Reading? {
        var calendar = Calendar.current
        calendar.timeZone = timeZone

        let temperatureNow: Int?
        if calendar.isDate(date, equalTo: fetchedAt, toGranularity: .hour) {
            temperatureNow = temperature
        } else {
            temperatureNow = hours.first {
                calendar.isDate($0.date, equalTo: date, toGranularity: .hour)
            }?.temperature
        }
        guard let temperatureNow else { return nil }

        let today = days.first { calendar.isDate($0.date, inSameDayAs: date) }

        return WeatherEntry.Reading(
            temperature: temperatureNow,
            low: today?.low,
            high: today?.high,
            nextHours: Array(hours.filter { $0.date > date }.prefix(3)),
            timeZone: timeZone,
            useCelsius: useCelsius
        )
    }

    /// Made-up but plausible, for the widget gallery and Xcode previews.
    static var preview: WidgetWeather {
        let calendar = Calendar.current
        let now = Date()
        let thisHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let icons = ["partlyCloudy", "cloudy", "rain", "storm", "cloudy", "clear_sun"]
        let hours = (1...24).map { offset in
            Hour(
                date: calendar.date(byAdding: .hour, value: offset, to: thisHour) ?? thisHour,
                iconName: icons[offset % icons.count],
                temperature: 68 - offset / 2
            )
        }
        let today = calendar.startOfDay(for: now)
        let days = (0..<2).map { offset in
            Day(date: calendar.date(byAdding: .day, value: offset, to: today) ?? today, high: 75, low: 58)
        }
        return WidgetWeather(
            temperature: 68,
            hours: hours,
            days: days,
            timeZoneIdentifier: TimeZone.current.identifier,
            useCelsius: false,
            source: nil,
            fetchedAt: now
        )
    }
}
