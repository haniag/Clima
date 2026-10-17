//
//  HourlyForecast.swift
//  Clima
//

import Foundation

/// A sunrise or a sunset. On the hourly strip it gets a column of its own, between the
/// two hours it falls between.
struct SunEvent: Hashable {
    enum Kind: Hashable {
        case sunrise
        case sunset
    }

    let kind: Kind
    /// The exact moment, to the second, the way the services report it.
    let date: Date

    /// The asset catalog image. Each has a light and a dark version, which iOS picks
    /// between by itself.
    var iconName: String {
        kind == .sunrise ? "sunrise" : "sunset"
    }

    /// The time to the minute on the 24-hour clock, e.g. "07:01" or "19:42", as a clock
    /// in `timeZone` — the place the weather is for — reads it.
    func timeLabel(in timeZone: TimeZone) -> String {
        let calendar = Calendar.local(to: timeZone)
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }

    /// What VoiceOver reads, since the icon alone says nothing to it.
    func accessibilityLabel(in timeZone: TimeZone) -> String {
        (kind == .sunrise ? "Sunrise at " : "Sunset at ") + timeLabel(in: timeZone)
    }
}

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

    /// Compact 24-hour label, e.g. "06", "13", "00" — just the hour, without ":00", so
    /// the columns stay narrow. The sunrise/sunset columns carry the minutes. In
    /// `timeZone`, the place the weather is for.
    func timeLabel(in timeZone: TimeZone) -> String {
        let hour = Calendar.local(to: timeZone).component(.hour, from: date)
        return String(format: "%02d", hour)
    }

}

extension Array where Element == HourlyForecast {
    /// Where the strip begins: the start of the hour AFTER the one `date` falls in. The
    /// hour we're in is already on screen — it's what the dial shows — so the strip opens
    /// on what's coming next.
    ///
    /// Hours are counted in `timeZone`, the place the weather is for. It matters even for
    /// the hour: in India, say, the clock's hours start at half past the phone's.
    static func stripStart(after date: Date, in timeZone: TimeZone = .current) -> Date {
        let calendar = Calendar.local(to: timeZone)
        let thisHour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return calendar.date(byAdding: .hour, value: 1, to: thisHour) ?? thisHour
    }

    /// Where the strip ends: midnight after the 7-day strip's last day. The hours cover
    /// the same seven days as the strip below them, so every day there has its hours to
    /// jump to — and no more, even though the new service's endpoint sends fifteen days.
    /// The hour starting here is the first one left off. Midnight in `timeZone`.
    static func stripEnd(after date: Date, in timeZone: TimeZone = .current) -> Date {
        let calendar = Calendar.local(to: timeZone)
        let today = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 7, to: today) ?? today
    }

    /// Every hour from `stripStart` up to `stripEnd`, with no weather against them — what
    /// the strip shows before there's a forecast, or when a service didn't send one.
    static func placeholder(from now: Date = Date(), in timeZone: TimeZone = .current) -> [HourlyForecast] {
        let calendar = Calendar.local(to: timeZone)
        let start = Self.stripStart(after: now, in: timeZone)
        let end = Self.stripEnd(after: now, in: timeZone)
        var hours: [HourlyForecast] = []
        var date = start
        while date < end {
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

extension [SunEvent] {
    /// Sunrise at 7:01 and sunset at 6:58 for today and the six days after it, to go with
    /// `[HourlyForecast].sample`, whose sun gives way to moons at 7PM. Previews only.
    static let sample: [SunEvent] = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).flatMap { day -> [SunEvent] in
            let start = calendar.date(byAdding: .day, value: day, to: today) ?? today
            return [
                SunEvent(kind: .sunrise, date: start.addingTimeInterval((7 * 60 + 1) * 60)),
                SunEvent(kind: .sunset, date: start.addingTimeInterval((18 * 60 + 58) * 60)),
            ]
        }
    }()
}
