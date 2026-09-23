//
//  DailyForecast.swift
//  Clima
//

import Foundation

/// One day's forecast for the horizontal 7-day strip shown below the dial.
struct DailyForecast: Identifiable {
    let id = UUID()
    /// The one value that's always known. A date needs no network and no permission, so
    /// the strip can lay out its seven columns with the right weekday letters even when
    /// there's nothing to put in them yet.
    let date: Date

    // Optional, all three, because a column with no reading behind it has to be able to
    // say so. The alternative — a placeholder temperature like 0 or -999 — puts a number
    // on screen that the eye reads as a measurement. `nil` can't be misread, and the
    // column renders it as a dash.
    let condition: WeatherCondition?
    let highTemp: Int?
    let lowTemp: Int?

    /// Single-letter weekday label, e.g. "M" for Monday. A few letters repeat
    /// (Tue/Thu, Sat/Sun) since it's the first letter, not a unique abbreviation.
    var dayLetter: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }
}

extension Array where Element == DailyForecast {
    /// The Monday of the week `date` falls in.
    ///
    /// The strip is a fixed Monday-to-Sunday week, so each weekday keeps the same column
    /// all week and "today" travels across the strip instead of the strip re-sorting
    /// itself underneath it every morning. Anchoring on today instead would mean the same
    /// weekday letter sat in a different place each day.
    ///
    /// Monday is hard-coded rather than taken from `Calendar.firstWeekday`, which is
    /// Sunday in the US and would quietly give a different week to different users.
    /// `.weekday` is always 1 = Sunday ... 7 = Saturday whatever the locale, so this
    /// arithmetic finds the most recent Monday everywhere.
    static func weekStart(containing date: Date) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
    }

    /// Monday to Sunday of the current week with no weather against them: what the strip
    /// shows before the first reading lands, and after one fails with nothing to fall
    /// back on.
    ///
    /// Built fresh on each call rather than stored in a `let`, since the current week
    /// moves and a constant computed at launch would still be showing last week come
    /// Monday morning.
    static func placeholder(from today: Date = Date()) -> [DailyForecast] {
        let calendar = Calendar.current
        let start = Self.weekStart(containing: today)
        return (0..<7).map { offset in
            DailyForecast(
                date: calendar.date(byAdding: .day, value: offset, to: start) ?? start,
                condition: nil,
                highTemp: nil,
                lowTemp: nil
            )
        }
    }

    /// Made-up but plausible data, for previews only. Nothing in the running app reads
    /// this any more — the strip is fed by WeatherKit, or by `placeholder` when there's
    /// no reading.
    static let sample: [DailyForecast] = {
        let calendar = Calendar.current
        let monday = [DailyForecast].weekStart(containing: Date())

        let conditions: [WeatherCondition] = [.clear, .partlyCloudy, .cloudy, .rain, .storm, .snow, .fog]
        return conditions.enumerated().map { index, condition in
            DailyForecast(
                date: calendar.date(byAdding: .day, value: index, to: monday) ?? monday,
                condition: condition,
                highTemp: 75 - index,
                lowTemp: 58 - index
            )
        }
    }()
}
