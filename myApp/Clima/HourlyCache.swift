//
//  HourlyCache.swift
//  Clima
//

import Foundation

/// Remembers each hour on the hourly strip from one fetch to the next, so an hour a
/// service can't fill any more still shows what it last said.
///
/// Now that the strip starts at the next hour, both services normally fill every
/// hour themselves, so this is just a fallback for an hour a forecast comes back without.
///
/// Each service gets its own, so switching sources never shows one service's hours
/// beside the other's. Kept in `UserDefaults`: it's a few dozen small entries, and it
/// should outlive quitting the app, since that's exactly when the hours go by unseen.
struct HourlyCache {

    private let key: String

    /// `source` names the service, and is part of the `UserDefaults` key.
    init(source: String) {
        key = "hourlyCache.\(source)"
    }

    /// `hours`, with any hour the service left empty filled in from the cache — then the
    /// result saved as the new cache.
    ///
    /// What the service sends always wins; the cache only fills gaps. A whole hour is
    /// taken from one place or the other, never its icon from one and its temperature
    /// from the other. Only the hours on the strip are saved, so ones that have scrolled
    /// off the back fall out on their own.
    func filling(_ hours: [HourlyForecast]) -> [HourlyForecast] {
        let saved = Dictionary(
            load().map { ($0.date, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        let filled = hours.map { hour -> HourlyForecast in
            guard hour.condition == nil, hour.temperature == nil, let entry = saved[hour.date] else {
                return hour
            }
            return HourlyForecast(
                date: hour.date,
                condition: entry.condition,
                temperature: entry.temperature,
                precipitationChance: entry.precipitationChance
            )
        }

        save(filled.compactMap { hour in
            guard hour.condition != nil || hour.temperature != nil else { return nil }
            return Entry(
                date: hour.date,
                condition: hour.condition,
                temperature: hour.temperature,
                precipitationChance: hour.precipitationChance
            )
        })
        return filled
    }

    /// One saved hour. Its own type rather than `HourlyForecast` itself, whose `id` is
    /// made fresh each time and has no business being saved.
    private struct Entry: Codable {
        let date: Date
        let condition: WeatherCondition?
        let temperature: Int?
        /// Optional, so entries saved before this field existed still decode.
        let precipitationChance: Int?
    }

    /// Nothing saved, or something that no longer decodes (after an app update changed
    /// `Entry`, say), both come back empty — the cache is a nicety, never a reason to fail.
    private func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func save(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
