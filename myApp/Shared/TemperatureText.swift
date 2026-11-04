//
//  TemperatureText.swift
//  Clima
//
//  Compiled into both the app and the widget extension, so the two can't disagree
//  about how a temperature reads.
//

/// Formats a Fahrenheit reading, converting to Celsius when the switch is on.
///
/// Only the degree sign is shown, never the unit: the unit is already stated once, by
/// the °F/°C switch in Settings. Repeating it on all 22 readings on screen is noise,
/// not information.
///
/// `nil` — no reading, for whatever reason — formats as a bare dash, with no degree sign
/// after it: a unit with nothing to qualify reads as a stray mark rather than as a
/// deliberate blank. Taking an optional here rather than making each caller unwrap is
/// what keeps that decision in one place, so every temperature on screen goes missing
/// the same way.
///
/// `degreeSign: false` drops the ° — the lock screen widget's choice, where every
/// character of width counts.
func temperatureText(_ fahrenheit: Int?, useCelsius: Bool, degreeSign: Bool = true) -> String {
    guard let fahrenheit else { return "—" }
    let value = useCelsius ? Int((Double(fahrenheit - 32) * 5 / 9).rounded()) : fahrenheit
    return degreeSign ? "\(value)°" : "\(value)"
}
