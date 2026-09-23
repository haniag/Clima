//
//  DailyForecastCache.swift
//  Clima
//

import Foundation

/// Remembers what we were last told about each day, so a day that has slipped into the
/// past still has something to show.
///
/// The 7-day strip is a fixed Monday-to-Sunday week, but WeatherKit only answers about
/// today onwards — so on a Thursday there is nothing to put in Monday, Tuesday or
/// Wednesday's columns, and they'd sit there as dashes. Every fetch writes down what it
/// knew; later fetches read those days back out.
///
/// Worth being clear about what's stored: a *forecast*, not an observation. Monday's
/// column on Thursday shows what Monday's own fetch predicted for Monday, which is not
/// quite the same as what Monday turned out to be. Filling those columns from WeatherKit's
/// historical API would be exact, at the cost of a second request per fetch; this costs
/// nothing and is close enough for four small numbers on a strip.
///
/// Consequence of caching rather than fetching: the cache only holds days the app was
/// actually opened on. Open it for the first time on a Thursday and Monday to Wednesday
/// are still dashes, because nothing ever saw them.
enum DailyForecastCache {

    /// One day's remembered reading.
    ///
    /// Deliberately its own type rather than `DailyForecast`: this is a disk format, and
    /// it shouldn't have to change shape every time the strip's model does. It also has
    /// no optionals — a day with nothing behind it simply isn't written — so decoding
    /// can't produce a half-empty entry.
    private struct Entry: Codable {
        let condition: WeatherCondition
        let highTemp: Int
        let lowTemp: Int
    }

    private static let defaultsKey = "cachedDailyForecasts"

    /// Remembers every day in `week` that actually has a reading.
    ///
    /// Days with nothing behind them are skipped rather than written as empty. That's the
    /// whole trick: a Thursday fetch knows nothing about Monday, and skipping means it
    /// leaves Monday's own entry alone instead of erasing it.
    static func save(_ week: [DailyForecast]) {
        var stored = load()

        for day in week {
            guard let condition = day.condition,
                  let highTemp = day.highTemp,
                  let lowTemp = day.lowTemp
            else { continue }
            stored[key(for: day.date)] = Entry(condition: condition, highTemp: highTemp, lowTemp: lowTemp)
        }

        // Days before this week's Monday will never be on the strip again, so they're
        // dropped here rather than left to pile up — this keeps the cache to about a
        // fortnight of days at its widest. Comparing the keys as strings works because
        // "yyyy-MM-dd" is zero-padded, which makes alphabetical order and chronological
        // order the same thing.
        let cutoff = key(for: [DailyForecast].weekStart(containing: Date()))
        stored = stored.filter { $0.key >= cutoff }

        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    /// Fills each day in `week` that has no reading with the last one we heard about it,
    /// and leaves every day that does have one untouched.
    ///
    /// Live data always wins, because a day only reaches the lookup if it arrived empty.
    /// So this can only ever fill the past days of the week, plus any future day a short
    /// answer from WeatherKit left blank.
    static func backfill(_ week: [DailyForecast]) -> [DailyForecast] {
        let stored = load()
        guard !stored.isEmpty else { return week }

        return week.map { day in
            guard day.condition == nil, let entry = stored[key(for: day.date)] else { return day }
            return DailyForecast(
                date: day.date,
                condition: entry.condition,
                highTemp: entry.highTemp,
                lowTemp: entry.lowTemp
            )
        }
    }

    // MARK: - Storage

    /// A day's own calendar date, as "2026-09-21" — so a reading can only ever come back
    /// out under the day it was about.
    ///
    /// Built from `Calendar.current` rather than a stored `DateFormatter` because a
    /// formatter holds the time zone it was created with, and this has to keep meaning
    /// "the day it is here" after the phone crosses one.
    private static func key(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Anything unreadable comes back as an empty cache rather than an error: a cache
    /// that can't be read is worth exactly as much as one that isn't there, and the strip
    /// already knows how to show a day it has nothing for.
    private static func load() -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return stored
    }
}
