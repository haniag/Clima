//
//  LocalCalendar.swift
//  Clima
//

import Foundation

extension Calendar {
    /// The phone's own calendar, but counting days and hours in `timeZone` — the time
    /// zone of the place the weather is for. With Paris chosen on a phone in Virginia,
    /// this is what makes Paris's sunrise read "07:58" rather than "01:58", and puts its
    /// midnight, not Virginia's, between one day's column and the next.
    ///
    /// `nonisolated` because the project puts code on the main actor by default, and the
    /// weather services use this off it.
    nonisolated static func local(to timeZone: TimeZone) -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar
    }
}
