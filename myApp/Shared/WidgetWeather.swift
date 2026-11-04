//
//  WidgetWeather.swift
//  Clima
//
//  Compiled into BOTH the app and the widget extension — see the `Shared` folder's
//  target membership. Keep it free of anything only one of them has (WeatherKit,
//  `WeatherSnapshot`, `Theme`).
//

import Foundation

/// What the lock screen widget shows, handed over from the app.
///
/// The widget runs in a process of its own and can't see the app's memory, so the app
/// writes its latest reading here — into the App Group both share — every time a fetch
/// lands, and the widget reads it back. The widget also fetches on its own every half
/// hour or so — same source, same place — and saves what it gets here too, so whichever
/// of the two fetched last is what both read.
///
/// Every hour of the forecast comes along, not just the next three, so the widget can
/// keep moving forward hour by hour even when a fetch of its own fails.
///
/// `nonisolated` because the app target puts types on the main actor by default.
nonisolated struct WidgetWeather: Codable {
    struct Hour: Codable, Hashable {
        /// The start of the hour.
        let date: Date
        /// The asset catalog name — `WeatherCondition.iconName` — or nil for an hour with
        /// no reading, which the widget shows as a dash.
        let iconName: String?
        /// Degrees Fahrenheit, like everywhere else in the app.
        let temperature: Int?
    }

    struct Day: Codable, Hashable {
        /// Midnight at the start of the day, in `timeZoneIdentifier`.
        let date: Date
        let high: Int?
        let low: Int?
    }

    /// Degrees Fahrenheit at the moment of the fetch.
    let temperature: Int
    /// From the hour after the fetch onward, one each.
    let hours: [Hour]
    /// Today and the days after it.
    let days: [Day]
    /// The place the weather is for, so the widget's hour labels read its clocks.
    let timeZoneIdentifier: String
    /// The °F/°C switch as it was when this was saved. The app saves again when it's
    /// flipped, so the widget follows it.
    let useCelsius: Bool
    /// Which service the app is reading from — `WeatherSource`'s raw value — so the
    /// widget's own fetches ask the same one. Passed along here because that choice is
    /// made in the Settings app, which saves it where only the app can read it.
    /// Optional so a reading saved before this was added still decodes.
    let source: String?
    let fetchedAt: Date

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    // MARK: - Storage

    /// The App Group both targets belong to. Must match the `App Groups` entry in
    /// `Clima.entitlements` and `ClimaWidget.entitlements`.
    static let appGroup = "group.com.fursa.Clima"

    /// The widget's `kind` — what the app names when it asks WidgetKit to redraw it.
    static let widgetKind = "ClimaLockScreen"

    private static let key = "widgetWeather"

    /// The last reading the app saved, or nil if it hasn't saved one yet.
    static var saved: WidgetWeather? {
        get {
            guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
            // Something that no longer decodes counts as nothing saved, rather than an error.
            return try? JSONDecoder().decode(WidgetWeather.self, from: data)
        }
        set {
            let defaults = UserDefaults(suiteName: appGroup)
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults?.set(data, forKey: key)
            } else {
                defaults?.removeObject(forKey: key)
            }
        }
    }
}
