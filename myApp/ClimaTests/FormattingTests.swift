//
//  FormattingTests.swift
//  ClimaTests
//
//  Checks the functions that turn a stored number or time into the text on screen.
//

import Foundation
import Testing
@testable import Clima

@MainActor
struct FormattingTests {

    // MARK: - Temperature

    @Test func fahrenheitIsShownAsStored() {
        #expect(temperatureText(72, useCelsius: false) == "72°")
        #expect(temperatureText(-5, useCelsius: false) == "-5°")
    }

    /// The app stores Fahrenheit and converts on the way to the screen.
    @Test(arguments: [(32, "0°"), (212, "100°"), (-40, "-40°"), (58, "14°"), (72, "22°"), (31, "-1°")])
    func celsiusIsConvertedAndRounded(fahrenheit: Int, expected: String) {
        #expect(temperatureText(fahrenheit, useCelsius: true) == expected)
    }

    /// No reading is a bare dash, with no degree sign after it, in either unit.
    @Test func missingTemperatureIsADash() {
        #expect(temperatureText(nil, useCelsius: false) == "—")
        #expect(temperatureText(nil, useCelsius: true) == "—")
    }

    /// The lock screen widget's form, where every character of width counts.
    @Test func degreeSignCanBeLeftOff() {
        #expect(temperatureText(72, useCelsius: false, degreeSign: false) == "72")
    }

    // MARK: - Wind

    @Test func wind() {
        #expect(windText(8.4, useMetric: false) == "8 mph")
        #expect(windText(10, useMetric: true) == "16 km/h")
        #expect(windText(0, useMetric: true) == "0 km/h")
        #expect(windText(nil, useMetric: false) == "—")
    }

    // MARK: - Precipitation

    /// Compared against the number formatted the same way rather than a fixed string,
    /// so the test passes on a machine whose region writes "0,02".
    @Test func precipitation() {
        let hundredths = (0.02).formatted(.number.precision(.fractionLength(2)))
        #expect(precipitationText(0.02, useMetric: false) == "\(hundredths) in")

        let millimetres = (25.4).formatted(.number.precision(.fractionLength(1)))
        #expect(precipitationText(1, useMetric: true) == "\(millimetres) mm")

        #expect(precipitationText(nil, useMetric: true) == "—")
    }

    // MARK: - Clock

    private let newYork = TimeZone(identifier: "America/New_York")!

    /// A moment on 25 September 2026, as a clock in New York reads it.
    private func time(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.local(to: newYork)
            .date(from: DateComponents(year: 2026, month: 9, day: 25, hour: hour, minute: minute))!
    }

    @Test func hourOn24HourClock() {
        #expect(ClockText.hour(time(0), in: newYork, uses12Hour: false) == "00")
        #expect(ClockText.hour(time(6), in: newYork, uses12Hour: false) == "06")
        #expect(ClockText.hour(time(13), in: newYork, uses12Hour: false) == "13")
    }

    /// Midnight and noon are the two a 12-hour clock gets wrong most easily.
    @Test func hourOn12HourClock() {
        #expect(ClockText.hour(time(0), in: newYork, uses12Hour: true) == "12AM")
        #expect(ClockText.hour(time(6), in: newYork, uses12Hour: true) == "6AM")
        #expect(ClockText.hour(time(12), in: newYork, uses12Hour: true) == "12PM")
        #expect(ClockText.hour(time(13), in: newYork, uses12Hour: true) == "1PM")
        #expect(ClockText.hour(time(23), in: newYork, uses12Hour: true) == "11PM")
    }

    @Test func hourAndMinute() {
        #expect(ClockText.hourMinute(time(7, 1), in: newYork, uses12Hour: false) == "07:01")
        #expect(ClockText.hourMinute(time(19, 42), in: newYork, uses12Hour: false) == "19:42")
        #expect(ClockText.hourMinute(time(7, 1), in: newYork, uses12Hour: true) == "7:01")
        #expect(ClockText.hourMinute(time(19, 42), in: newYork, uses12Hour: true) == "7:42")
    }

    /// The same moment reads differently in the place the weather is for.
    @Test func timesFollowThePlacesClock() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        #expect(ClockText.hour(time(13), in: paris, uses12Hour: false) == "19")
    }

    // MARK: - Where the hourly strip starts and ends

    /// The strip opens on the hour after the one we're in — the dial already shows this
    /// one — and ends at midnight after the 7-day strip's last day.
    @Test func hourlyStripWindow() {
        let calendar = Calendar.local(to: newYork)
        let start = [HourlyForecast].stripStart(after: time(12, 25), in: newYork)
        #expect(start == time(13))

        let end = [HourlyForecast].stripEnd(after: time(12, 25), in: newYork)
        #expect(end == calendar.date(from: DateComponents(year: 2026, month: 10, day: 2)))

        // One column per hour, with none missing and none doubled.
        let hours = [HourlyForecast].placeholder(from: time(12, 25), in: newYork)
        #expect(hours.first?.date == start)
        #expect(hours.count == 11 + 6 * 24)
    }
}
