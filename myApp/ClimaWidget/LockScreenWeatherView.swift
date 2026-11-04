//
//  LockScreenWeatherView.swift
//  ClimaWidget
//

import SwiftUI
import WidgetKit

/// The rectangular lock screen widget's face.
///
/// Left: an arc from today's low (bottom left) to today's high (bottom right), with the
/// temperature now in its middle and a marker along the arc at where it sits between
/// the two. Right: the next three hours, each a column of hour, icon and temperature —
/// the same three rows as the app's hourly strip.
///
/// The lock screen draws everything in one tint, so nothing here sets a colour. The
/// condition icons are template images (see their Contents.json) and take the tint too.
struct LockScreenWeatherView: View {
    let entry: WeatherEntry

    var body: some View {
        Group {
            if let reading = entry.reading {
                HStack(spacing: 6) {
                    temperatureGauge(reading)
                    hourColumns(reading)
                }
            } else {
                Text("Open Clima to load the weather")
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Required on iOS 17 and later. Clear, because the lock screen draws its own
        // backing behind accessory widgets.
        .containerBackground(for: .widget) { Color.clear }
    }

    private func temperatureGauge(_ reading: WeatherEntry.Reading) -> some View {
        // Positions are worked out in °F whatever the switch says: converting to °C
        // stretches the low, the high and the reading alike, so the marker lands in the
        // same place either way.
        //
        // The range is widened to take in the reading itself, because today's forecast
        // low and high can be overtaken by what's actually happening — the marker then
        // sits at the end of the arc rather than off it.
        let low = min(reading.low ?? reading.temperature, reading.temperature)
        var high = max(reading.high ?? reading.temperature, reading.temperature)
        if high <= low { high = low + 1 }

        return Gauge(value: Double(reading.temperature), in: Double(low)...Double(high)) {
            Text("Temperature")
        } currentValueLabel: {
            Text(temperatureText(reading.temperature, useCelsius: reading.useCelsius, degreeSign: false))
        } minimumValueLabel: {
            Text(temperatureText(reading.low, useCelsius: reading.useCelsius, degreeSign: false))
        } maximumValueLabel: {
            Text(temperatureText(reading.high, useCelsius: reading.useCelsius, degreeSign: false))
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Now \(temperatureText(reading.temperature, useCelsius: reading.useCelsius, degreeSign: false)), "
                + "low \(temperatureText(reading.low, useCelsius: reading.useCelsius, degreeSign: false)), "
                + "high \(temperatureText(reading.high, useCelsius: reading.useCelsius, degreeSign: false))"
        )
    }

    private func hourColumns(_ reading: WeatherEntry.Reading) -> some View {
        HStack(spacing: 0) {
            ForEach(reading.nextHours, id: \.self) { hour in
                VStack(spacing: 2) {
                    Text(hourLabel(hour.date, in: reading.timeZone))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Group {
                        if let iconName = hour.iconName {
                            Image(iconName)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Text("—")
                        }
                    }
                    .frame(width: 18, height: 18)

                    Text(temperatureText(hour.temperature, useCelsius: reading.useCelsius, degreeSign: false))
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(hourLabel(hour.date, in: reading.timeZone)):00, "
                        + temperatureText(hour.temperature, useCelsius: reading.useCelsius, degreeSign: false)
                )
            }
        }
    }

    /// "06", "13", "00" — the same 24-hour label as the app's hourly strip, in the time
    /// zone of the place the weather is for.
    private func hourLabel(_ date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return String(format: "%02d", calendar.component(.hour, from: date))
    }
}

#Preview("Reading", as: .accessoryRectangular) {
    ClimaLockScreenWidget()
} timeline: {
    WeatherEntry(date: .now, reading: WidgetWeather.preview.reading(at: .now))
}

#Preview("Nothing saved yet", as: .accessoryRectangular) {
    ClimaLockScreenWidget()
} timeline: {
    WeatherEntry(date: .now, reading: nil)
}
