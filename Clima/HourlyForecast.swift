//
//  HourlyForecast.swift
//  Clima
//

import Foundation

/// One hour in the hourly strip shown below the 7-day forecast.
struct HourlyForecast: Identifiable {
    let id = UUID()
    /// The start of the hour. Always known, the same way `DailyForecast.date` is — it's
    /// what lets the strip keep its time labels with nothing to show against them.
    let date: Date

    // Optional for the same reason as `DailyForecast`'s: an hour with no reading renders
    // a dash rather than a number that was never measured.
    let condition: WeatherCondition?
    let temperature: Int?
    /// Chance of rain, snow, etc. during the hour, as a whole percent (0–100).
    let precipitationChance: Int?

    /// Compact time label, e.g. "6AM", "12PM" — a fixed short form (not DateFormatter's
    /// localized "6 AM") so the columns stay narrow.
    var timeLabel: String {
        let hour = Calendar.current.component(.hour, from: date)
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        let period = hour < 12 ? "AM" : "PM"
        return "\(displayHour)\(period)"
    }

    /// Whether this is the first hour of a day. On the strip, that column starts a new day.
    var isMidnight: Bool {
        Calendar.current.component(.hour, from: date) == 0
    }

    /// Whether `now` falls inside this hour.
    func contains(_ now: Date) -> Bool {
        let end = Calendar.current.date(byAdding: .hour, value: 1, to: date) ?? date
        return now >= date && now < end
    }
}

extension Array where Element == HourlyForecast {
    /// How many hours before the current one the strip reaches back.
    static let pastHourCount = 3

    /// Where the strip begins: three hours before the one `date` falls in.
    ///
    /// Those three have already happened, so they show what the weather was rather than
    /// what it will be — WeatherKit can say, and for the new service they come from
    /// `HourlyCache`.
    static func stripStart(containing date: Date) -> Date {
        let calendar = Calendar.current
        let thisHour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return calendar.date(byAdding: .hour, value: -pastHourCount, to: thisHour) ?? thisHour
    }

    /// Where the strip ends: the midnight at the end of tomorrow, which is included as the
    /// last column. So it always runs through the rest of today and all of tomorrow, and
    /// how many columns that is depends on the time of day.
    static func stripEnd(containing date: Date) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 2, to: today) ?? today
    }

    /// Every hour from `stripStart` to `stripEnd`, both included, with no weather against
    /// them — the slots the services match their forecasts into.
    ///
    /// Stepped an hour at a time rather than counted, so a daylight-saving change, which
    /// makes a day 23 or 25 hours long, still gives each real hour exactly one column.
    static func placeholder(from now: Date = Date()) -> [HourlyForecast] {
        let calendar = Calendar.current
        let end = Self.stripEnd(containing: now)
        var hours: [HourlyForecast] = []
        var date = Self.stripStart(containing: now)
        while date <= end {
            hours.append(HourlyForecast(date: date, condition: nil, temperature: nil, precipitationChance: nil))
            guard let next = calendar.date(byAdding: .hour, value: 1, to: date) else { break }
            date = next
        }
        return hours
    }

    /// Made-up but plausible data, for previews only — the running app no longer reads it.
    static let sample: [HourlyForecast] = {
        let conditions: [WeatherCondition] = [.clear, .partlyCloudy, .cloudy, .rain, .storm, .cloudy]
        return placeholder().enumerated().map { index, hour in
            let hourOfDay = Calendar.current.component(.hour, from: hour.date)
            return HourlyForecast(
                date: hour.date,
                // In the sun from 7AM to 6PM, and moons the rest of the time.
                condition: (7..<19).contains(hourOfDay) ? conditions[index % conditions.count] : .partlyCloudyNight,
                // Coolest around 3AM, warmest around 3PM.
                temperature: 58 + 12 - abs(hourOfDay - 15),
                // Every third hour clears the threshold, so the preview shows both a
                // number and a dash.
                precipitationChance: index % 3 == 0 ? 70 : 20
            )
        }
    }()
}
