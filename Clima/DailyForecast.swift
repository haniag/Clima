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
    /// Midnight on the day `date` falls in — where the strip always begins.
    ///
    /// The strip is today and the six days after it, so today is always the first
    /// column, and its position is enough to say so without a "today" marker. It also
    /// keeps every column inside what WeatherKit's daily forecast covers, which starts at
    /// today as well — there's no day on the strip that's already over and so has no
    /// forecast left to show.
    static func stripStart(containing date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    /// Today and the six days after it with no weather against them: what the strip
    /// shows before the first reading lands, and after one fails with nothing to fall
    /// back on.
    ///
    /// Built fresh on each call rather than stored in a `let`, since today moves and a
    /// constant computed at launch would still be starting on yesterday come midnight.
    static func placeholder(from today: Date = Date()) -> [DailyForecast] {
        let calendar = Calendar.current
        let start = Self.stripStart(containing: today)
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
        let today = [DailyForecast].stripStart(containing: Date())

        let conditions: [WeatherCondition] = [.clear, .partlyCloudy, .cloudy, .rain, .storm, .snow, .fog]
        return conditions.enumerated().map { index, condition in
            DailyForecast(
                date: calendar.date(byAdding: .day, value: index, to: today) ?? today,
                condition: condition,
                highTemp: 75 - index,
                lowTemp: 58 - index
            )
        }
    }()
}
