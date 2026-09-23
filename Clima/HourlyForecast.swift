//
//  HourlyForecast.swift
//  Clima
//

import Foundation

/// One 3-hour block in the hourly strip shown below the 7-day forecast.
struct HourlyForecast: Identifiable {
    let id = UUID()
    /// Always known, the same way `DailyForecast.date` is — it's what lets the strip keep
    /// its eight time labels with nothing to show against them.
    let date: Date

    // Optional for the same reason as `DailyForecast`'s: a block with no reading renders
    // a dash rather than a number that was never measured.
    let condition: WeatherCondition?
    let temperature: Int?

    /// Compact time label, e.g. "6AM", "12PM" — a fixed short form (not DateFormatter's
    /// localized "6 AM") so all 8 columns stay narrow enough to fit in one row.
    var timeLabel: String {
        let hour = Calendar.current.component(.hour, from: date)
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        let period = hour < 12 ? "AM" : "PM"
        return "\(displayHour)\(period)"
    }

    /// Whether `now` falls inside this block's 3-hour window.
    func contains(_ now: Date) -> Bool {
        let blockEnd = Calendar.current.date(byAdding: .hour, value: 3, to: date) ?? date
        return now >= date && now < blockEnd
    }
}

extension Array where Element == HourlyForecast {
    /// Midnight on the day `date` falls in — where the strip always begins.
    ///
    /// Eight blocks three hours apart from there is exactly 24 hours, so the strip holds
    /// one calendar day, midnight to midnight, and nothing else. Two things follow from
    /// that. The eight labels never change, so the strip stops re-labelling itself while
    /// you're looking at it. And the current moment is always inside the window — it's
    /// always some hour of today — so the "now" marker always has a column to sit on,
    /// which an anchor part-way through the day can't promise.
    static func stripStart(containing date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    /// The same eight 3-hour blocks the real strip uses — see
    /// `WeatherService.hourlyBlocks(from:)` — but with no weather against them.
    static func placeholder(from now: Date = Date()) -> [HourlyForecast] {
        let start = Self.stripStart(containing: now)
        return (0..<8).map { index in
            HourlyForecast(
                date: Calendar.current.date(byAdding: .hour, value: index * 3, to: start) ?? start,
                condition: nil,
                temperature: nil
            )
        }
    }

    /// Made-up but plausible data, for previews only — the running app no longer reads it.
    static let sample: [HourlyForecast] = {
        let calendar = Calendar.current
        let midnight = [HourlyForecast].stripStart(containing: Date())

        let conditions: [WeatherCondition] = [.clear, .partlyCloudy, .cloudy, .rain, .storm, .cloudy, .clear, .fog]
        return conditions.enumerated().map { index, condition in
            HourlyForecast(
                date: calendar.date(byAdding: .hour, value: index * 3, to: midnight) ?? midnight,
                condition: condition,
                temperature: 75 - index
            )
        }
    }()
}
