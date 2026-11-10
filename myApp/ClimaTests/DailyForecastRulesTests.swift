//
//  DailyForecastRulesTests.swift
//  ClimaTests
//
//  Checks how the new weather service's 15-day forecast becomes the 7-day strip's
//  columns — in particular the rules for today, which change as the day goes on.
//

import Foundation
import Testing
@testable import Clima

@MainActor
struct DailyForecastRulesTests {

    private let newYork = TimeZone(identifier: "America/New_York")!
    private var calendar: Calendar { Calendar.local(to: newYork) }

    /// A moment on "today" — 25 September 2026 — as a clock in New York reads it.
    private func today(at hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: hour))!
    }

    /// A forecast shaped like the service's, starting today, with a sunset at 19:03.
    ///
    /// Today's values can each be set or left out (`nil`, which the service sends as
    /// `null`); every later day is partly cloudy (30) by day, mostly clear (33) by
    /// night, 70° over 55°, with a 20% chance of rain.
    private func forecast(
        days: Int = 10,
        todayDayIcon: Int? = 32,
        todayNightIcon: Int? = 31,
        todayHigh: Double? = 75,
        todayDayRain: Double? = 10
    ) throws -> FifteenDayForecast {
        func json(_ value: Any?) -> Any { value ?? NSNull() }
        let later = days - 1

        let midnight = today(at: 0)
        let body: [String: Any] = [
            // The service stamps each day at 7 in the morning, local time.
            "validTimeUtc": (0..<days).map {
                calendar.date(byAdding: .day, value: $0, to: midnight)!.timeIntervalSince1970 + 7 * 3600
            },
            "temperatureMax": [json(todayHigh)] + Array(repeating: 70.0 as Any, count: later),
            "temperatureMin": Array(repeating: 55.0, count: days),
            "calendarDayTemperatureMax": [78.0] + Array(repeating: 70.0, count: later),
            "calendarDayTemperatureMin": Array(repeating: 52.0, count: days),
            "sunriseTimeLocal": ["2026-09-25T07:00:23-0400"] + Array(repeating: NSNull() as Any, count: later),
            "sunsetTimeLocal": ["2026-09-25T19:03:12-0400"] + Array(repeating: NSNull() as Any, count: later),
            "daypart": [[
                // Day, then night, for each day in turn.
                "iconCode": [json(todayDayIcon), json(todayNightIcon)]
                    + (0..<later).flatMap { _ in [30 as Any, 33 as Any] },
                "precipChance": [json(todayDayRain), 40.0 as Any]
                    + (0..<later).flatMap { _ in [20.0 as Any, 20.0 as Any] },
            ]],
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        return try JSONDecoder().decode(FifteenDayForecast.self, from: data)
    }

    private func columns(_ forecast: FifteenDayForecast, at hour: Int) -> [DailyForecast] {
        NewWeatherService.dailyForecasts(from: forecast, today: today(at: hour), in: newYork)
    }

    /// Seven columns, today first, one per day.
    @Test func sevenDaysStartingToday() throws {
        let days = columns(try forecast(), at: 12)
        #expect(days.count == 7)
        for (offset, day) in days.enumerated() {
            #expect(day.date == calendar.date(byAdding: .day, value: offset, to: today(at: 0)))
        }
    }

    @Test func duringTheDayTodayShowsItsDaytimeForecast() throws {
        let day = columns(try forecast(), at: 12)[0]
        #expect(day.condition == .clear)
        #expect(day.highTemp == 75)
        #expect(day.lowTemp == 55)
        #expect(day.precipitationChance == 10)
    }

    /// After sunset, today is the one column that shows a moon.
    @Test func afterSunsetTodayShowsTonight() throws {
        let days = columns(try forecast(), at: 20)
        #expect(days[0].condition == .clearNight)
        // Tomorrow is still a whole day, and keeps its sun.
        #expect(days[1].condition == .partlyCloudy)
    }

    /// Around 3pm the service drops today's daytime values. Until sunset the column
    /// borrows the night's icon — with its sun put back — and the calendar-day high.
    @Test func lateAfternoonFillsInWhatTheServiceDropped() throws {
        let dropped = try forecast(todayDayIcon: nil, todayHigh: nil, todayDayRain: nil)
        let day = columns(dropped, at: 16)[0]
        #expect(day.condition == .clear)
        #expect(day.highTemp == 78)
        #expect(day.precipitationChance == 40)
    }

    /// A day the forecast doesn't reach shows dashes in its own column, and the days it
    /// does reach stay under their own letters.
    @Test func daysTheForecastDoesNotCoverAreEmpty() throws {
        let days = columns(try forecast(days: 3), at: 12)
        #expect(days.count == 7)
        #expect(days[2].condition == .partlyCloudy)
        #expect(days[3].condition == nil)
        #expect(days[3].highTemp == nil)
        #expect(days[6].precipitationChance == nil)
    }

    /// A reading that's been saved and read back says the same thing — the round trip
    /// behind opening the app on the last reading.
    @Test func aSavedReadingSurvivesTheRoundTrip() async throws {
        let original = try await PreviewWeatherService(condition: .storm, temperature: 41).currentWeather()
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(WeatherSnapshot.self, from: data)

        #expect(restored.condition == .storm)
        #expect(restored.temperature == 41)
        #expect(restored.windSpeed == original.windSpeed)
        #expect(restored.fetchedAt == original.fetchedAt)
        #expect(restored.daily.map(\.date) == original.daily.map(\.date))
        #expect(restored.daily.map(\.highTemp) == original.daily.map(\.highTemp))
        #expect(restored.hourly.map(\.temperature) == original.hourly.map(\.temperature))
        #expect(restored.sunEvents == original.sunEvents)
    }
}
