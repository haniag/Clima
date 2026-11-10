//
//  WeatherConditionTests.swift
//  ClimaTests
//
//  Checks the two tables that turn a weather service's own conditions into the dial's
//  slots. Run with Product ▸ Test (⌘U) in Xcode.
//

import Testing
import WeatherKit
@testable import Clima

/// Both WeatherKit and the app have a type called `WeatherCondition`, and this file
/// imports both, so the app's gets a name here that can't be mistaken for the other.
private typealias Condition = Clima.WeatherCondition

/// `@MainActor` because the app puts its own types on the main actor by default, and a
/// test has to be there too to use them.
@MainActor
struct WeatherConditionTests {

    // MARK: - The new service's icon codes

    /// The codes we were given a mapping for — the ones marked "agreed" in
    /// `WeatherCondition.init(iconCode:)`.
    @Test(arguments: [
        (4, Condition.storm),
        (12, .rain),
        (16, .snow),
        (24, .windy),
        (26, .cloudy),
        (30, .partlyCloudy),
        (31, .clearNight),
        (32, .clear),
        (33, .partlyCloudyNight),
    ])
    private func agreedIconCodes(code: Int, expected: Condition) {
        #expect(Condition(iconCode: code) == expected)
    }

    /// 44 is the service's "not available", and anything outside 0–47 is a code the
    /// table has never heard of. Both fall back to cloudy rather than crashing or
    /// claiming sunshine.
    @Test(arguments: [44, 48, -1, 999])
    func unknownIconCodesAreCloudy(code: Int) {
        #expect(Condition(iconCode: code) == .cloudy)
    }

    /// Every code the service can send lands on something — a slot on the dial, or a
    /// night version that borrows one.
    @Test func everyIconCodeHasADialSlot() {
        for code in 0...47 {
            let slot = Condition(iconCode: code).dialSlot
            #expect(Condition.dialSlots.contains(slot), "code \(code)")
        }
    }

    // MARK: - WeatherKit's conditions

    /// Only the conditions with a sun in their icon change after dark.
    @Test func weatherKitDayAndNight() {
        #expect(Condition(weatherKitCondition: .clear, isDaylight: true) == .clear)
        #expect(Condition(weatherKitCondition: .clear, isDaylight: false) == .clearNight)
        #expect(Condition(weatherKitCondition: .partlyCloudy, isDaylight: true) == .partlyCloudy)
        #expect(Condition(weatherKitCondition: .partlyCloudy, isDaylight: false) == .partlyCloudyNight)
        #expect(Condition(weatherKitCondition: .rain, isDaylight: true) == .rain)
        #expect(Condition(weatherKitCondition: .rain, isDaylight: false) == .rain)
    }

    @Test func weatherKitBuckets() {
        #expect(Condition(weatherKitCondition: .foggy, isDaylight: true) == .cloudy)
        #expect(Condition(weatherKitCondition: .drizzle, isDaylight: true) == .rain)
        #expect(Condition(weatherKitCondition: .thunderstorms, isDaylight: true) == .storm)
        #expect(Condition(weatherKitCondition: .sleet, isDaylight: true) == .snow)
        #expect(Condition(weatherKitCondition: .breezy, isDaylight: true) == .windy)
    }

    // MARK: - The dial

    /// A clear night has no slot of its own: it sits in clear's, at clear's angle.
    @Test func clearNightSharesClearsSlot() {
        #expect(Condition.clearNight.dialSlot == .clear)
        #expect(Condition.clearNight.angle == Condition.clear.angle)
    }

    /// Eight slots, evenly spaced, no two at the same angle.
    @Test func slotsAreEvenlySpaced() {
        let angles = Condition.dialSlots.map(\.angle)
        #expect(Set(angles).count == Condition.dialSlots.count)
        #expect(angles == angles.sorted())
        #expect(angles.first == 0)
        #expect(angles.last == 360 - 360 / Double(Condition.dialSlots.count))
    }
}
