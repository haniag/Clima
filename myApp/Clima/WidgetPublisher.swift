//
//  WidgetPublisher.swift
//  Clima
//
//  Compiled into the widget extension too (see its Target Membership), which uses
//  `init(_:useCelsius:source:)` to save the readings it fetches itself.
//

import WidgetKit

extension WidgetWeather {
    /// What the widget needs from `snapshot`: plain numbers and icon names.
    ///
    /// Lives here rather than in Shared/ because it's the one place that knows both
    /// sides: `WeatherSnapshot` and `WeatherCondition` belong to the weather services,
    /// not to the widget's own code.
    init(_ snapshot: WeatherSnapshot, useCelsius: Bool, source: WeatherSource) {
        self.init(
            temperature: snapshot.temperature,
            hours: snapshot.hourly.map {
                Hour(date: $0.date, iconName: $0.condition?.iconName, temperature: $0.temperature)
            },
            days: snapshot.daily.map {
                Day(date: $0.date, high: $0.highTemp, low: $0.lowTemp)
            },
            timeZoneIdentifier: snapshot.timeZone.identifier,
            useCelsius: useCelsius,
            source: source.rawValue,
            fetchedAt: snapshot.fetchedAt
        )
    }

    /// Hands `snapshot` to the lock screen widget and asks it to redraw. App only — the
    /// widget saves its own fetches without asking itself to reload, which would loop.
    ///
    /// Called from the screen on every successful fetch and when the °F/°C switch flips.
    /// A reload asked for while the app is on screen doesn't count against the widget's
    /// daily refresh budget.
    static func publish(_ snapshot: WeatherSnapshot, useCelsius: Bool) {
        saved = WidgetWeather(snapshot, useCelsius: useCelsius, source: WeatherSource.current)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
