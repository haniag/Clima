//
//  WeatherCondition.swift
//  Clima
//

import SwiftUI
import WeatherKit

/// The weather conditions the app can show. Eight of them are the dial's slots (see
/// `dialSlots`); the rest are night versions that borrow a slot rather than taking one.
enum WeatherCondition: Hashable, Codable {
    case clear
    case clearNight
    case partlyCloudy
    case cloudy
    case windy
    case rain
    case storm
    case snow
    case partlyCloudyNight

    /// Name of the custom vector icon in Assets.xcassets (matches a WeatherKit condition).
    var iconName: String {
        switch self {
        case .clear: return "clear_sun"
        case .clearNight: return "clear_moon"
        case .partlyCloudy: return "partlyCloudy"
        case .cloudy: return "cloudy"
        case .windy: return "windy"
        case .rain: return "rain"
        case .storm: return "storm"
        case .snow: return "snow"
        case .partlyCloudyNight: return "partlyCloudy_Moon"
        }
    }

    /// Human-readable label, e.g. for "Rainy & 90°" under the dial.
    var label: String {
        switch self {
        case .clear: return "Sunny"
        case .clearNight: return "Clear"
        case .partlyCloudy: return "Partly Cloudy"
        case .cloudy: return "Cloudy"
        case .windy: return "Windy"
        case .rain: return "Rainy"
        case .storm: return "Stormy"
        case .snow: return "Snowy"
        case .partlyCloudyNight: return "Partly Cloudy"
        }
    }

    /// The dial's slots, in order around the wheel — this list IS the dial's layout, so
    /// keep it small and deliberate.
    static let dialSlots: [WeatherCondition] = [
        .clear, .partlyCloudy, .cloudy, .windy, .rain, .storm, .snow, .partlyCloudyNight,
    ]

    /// Which slot on the dial this condition lives in. Usually its own; a clear night
    /// has no room for a slot of its own, so it shares clear's and the dial swaps the
    /// sun there for a moon while it's the current condition.
    var dialSlot: WeatherCondition {
        self == .clearNight ? .clear : self
    }

    /// Fixed angle in degrees around the dial, evenly spaced, 0° at the top and increasing clockwise.
    var angle: Double {
        let index = Double(Self.dialSlots.firstIndex(of: dialSlot)!)
        return index * (360.0 / Double(Self.dialSlots.count))
    }
}

extension WeatherCondition {
    /// Buckets one of WeatherKit's ~30 fine-grained conditions into our 8 dial positions.
    /// This is the one place that mapping lives — everything else just works off our
    /// own `WeatherCondition`, so WeatherKit's specifics never leak past this point.
    ///
    /// `isDaylight` is WeatherKit's own flag for whether the sun is up at that place and
    /// time. It only matters for the conditions whose icon has a sun in it — clear and
    /// partly cloudy — which get their moon versions after dark.
    init(weatherKitCondition: WeatherKit.WeatherCondition, isDaylight: Bool) {
        switch weatherKitCondition {
        case .clear, .mostlyClear, .hot:
            self = isDaylight ? .clear : .clearNight

        case .partlyCloudy:
            self = isDaylight ? .partlyCloudy : .partlyCloudyNight

        // Fog lost its own slot on the dial to partly-cloudy-at-night, so it joins the
        // other "grey sky, nothing falling" conditions here.
        case .cloudy, .mostlyCloudy, .foggy, .haze, .smoky, .blowingDust, .frigid:
            self = .cloudy

        case .breezy, .windy:
            self = .windy

        case .drizzle, .rain, .heavyRain, .freezingDrizzle, .freezingRain,
             .sunShowers, .isolatedThunderstorms, .scatteredThunderstorms:
            self = .rain

        case .thunderstorms, .strongStorms, .hurricane, .tropicalStorm:
            self = .storm

        case .snow, .flurries, .heavySnow, .blowingSnow, .blizzard,
             .sunFlurries, .wintryMix, .sleet, .hail:
            self = .snow

        @unknown default:
            self = .cloudy
        }
    }
}

extension WeatherCondition {
    /// Buckets the new weather service's `iconCode` (0–47) into our dial positions — the
    /// same job `init(weatherKitCondition:isDaylight:)` does for WeatherKit, for
    /// the new weather service.
    ///
    /// The codes marked "agreed" are the ones we were given a mapping for. The rest are
    /// the other codes that service can send, bucketed by what they mean, the same way the
    /// WeatherKit mapping above buckets its ~30 conditions. Unlike WeatherKit, day and
    /// night are already part of the code (31 is a clear night, 32 a clear day), so no
    /// separate daylight flag is needed.
    init(iconCode: Int) {
        switch iconCode {
        // Tornado, tropical storm, hurricane, strong storms, thunderstorms (4: agreed).
        case 0, 1, 2, 3, 4:
            self = .storm

        // Drizzle, freezing drizzle/rain, showers, rain (12: agreed), isolated and
        // scattered thunderstorms, scattered showers, heavy rain.
        case 8, 9, 10, 11, 12, 37, 38, 39, 40, 45, 47:
            self = .rain

        // Rain/snow and rain/sleet mixes, wintry mix, flurries, snow showers, blowing
        // snow, snow (16: agreed), hail, sleet, rain and hail, heavy snow, blizzard.
        case 5, 6, 7, 13, 14, 15, 16, 17, 18, 35, 41, 42, 43, 46:
            self = .snow

        // Dust, fog, haze, smoke, frigid, cloudy (26: agreed), mostly cloudy by night
        // and by day.
        case 19, 20, 21, 22, 25, 26, 27, 28:
            self = .cloudy

        // Breezy and windy (24: agreed).
        case 23, 24:
            self = .windy

        // Partly cloudy (30: agreed) and mostly sunny, by day.
        case 30, 34:
            self = .partlyCloudy

        // Partly cloudy and mostly clear (33: agreed), by night.
        case 29, 33:
            self = .partlyCloudyNight

        // Sunny (32: agreed) and hot.
        case 32, 36:
            self = .clear

        // Clear night (31: agreed).
        case 31:
            self = .clearNight

        // 44 is "not available", and anything else is a code this list doesn't know.
        // Cloudy is the same fallback WeatherKit's unknown conditions get.
        default:
            self = .cloudy
        }
    }
}
