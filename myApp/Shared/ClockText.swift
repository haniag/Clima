//
//  ClockText.swift
//  Clima
//
//  Compiled into both the app and the widget extension, so the two can't disagree
//  about how a time reads.
//

import Foundation

/// Writes the times on the hourly strip and the lock screen widget the way the phone's
/// own clock is set: "13" and "07:01" on a 24-hour phone, "1PM" and "7:01" on a 12-hour
/// one.
///
/// `nonisolated` because both targets put code on the main actor by default, and the
/// widget asks for these from off it.
nonisolated enum ClockText {

    /// Whether the phone shows 12-hour time — its region's habit, or the 24-Hour Time
    /// switch in Settings ▸ General ▸ Date & Time when that's been set by hand.
    static var uses12Hour: Bool {
        switch Locale.current.hourCycle {
        case .oneToTwelve, .zeroToEleven: true
        default: false
        }
    }

    /// The hour alone, for a column heading: "06", "13", "00" — or "6AM", "1PM", "12AM".
    /// No ":00", so the columns stay narrow. As a clock in `timeZone` reads it.
    ///
    /// `uses12Hour` is a parameter so a test can ask for either form whatever the
    /// machine running it is set to; everything else leaves it at the phone's setting.
    static func hour(_ date: Date, in timeZone: TimeZone, uses12Hour: Bool = ClockText.uses12Hour) -> String {
        let hour = components(of: date, in: timeZone).hour
        guard uses12Hour else { return String(format: "%02d", hour) }
        return "\(hour % 12 == 0 ? 12 : hour % 12)\(hour < 12 ? "AM" : "PM")"
    }

    /// The time to the minute, for a sunrise or sunset: "07:01", "19:42" — or "7:01",
    /// "7:42". The 12-hour form carries no AM or PM: it sits over a sunrise or sunset
    /// icon, which already says which half of the day it is, and the column is too
    /// narrow for both.
    static func hourMinute(_ date: Date, in timeZone: TimeZone, uses12Hour: Bool = ClockText.uses12Hour) -> String {
        let (hour, minute) = components(of: date, in: timeZone)
        guard uses12Hour else { return String(format: "%02d:%02d", hour, minute) }
        return String(format: "%d:%02d", hour % 12 == 0 ? 12 : hour % 12, minute)
    }

    private static func components(of date: Date, in timeZone: TimeZone) -> (hour: Int, minute: Int) {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return (calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }
}
