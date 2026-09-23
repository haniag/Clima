//
//  WeatherCondition.swift
//  Clima
//

import SwiftUI
import WeatherKit

/// The fixed, ordered set of weather conditions shown on the dial.
/// Order here defines position around the dial — keep this list small and deliberate.
enum WeatherCondition: CaseIterable, Hashable {
    case clear
    case partlyCloudy
    case cloudy
    case rain
    case storm
    case snow
    case fog

    /// Name of the custom vector icon in Assets.xcassets (matches a WeatherKit condition).
    var iconName: String {
        switch self {
        case .clear: return "clear_sun"
        case .partlyCloudy: return "partlyCloudy"
        case .cloudy: return "cloudy"
        case .rain: return "rain"
        case .storm: return "storm"
        case .snow: return "snow"
        case .fog: return "fog"
        }
    }

    /// Human-readable label, e.g. for "Rainy & 90°" under the dial.
    var label: String {
        switch self {
        case .clear: return "Sunny"
        case .partlyCloudy: return "Partly Cloudy"
        case .cloudy: return "Cloudy"
        case .rain: return "Rainy"
        case .storm: return "Stormy"
        case .snow: return "Snowy"
        case .fog: return "Foggy"
        }
    }

    /// Fixed angle in degrees around the dial, evenly spaced, 0° at the top and increasing clockwise.
    var angle: Double {
        let index = Double(Self.allCases.firstIndex(of: self)!)
        return index * (360.0 / Double(Self.allCases.count))
    }
}

extension WeatherCondition {
    /// Buckets one of WeatherKit's ~30 fine-grained conditions into our 7 dial positions.
    /// This is the one place that mapping lives — everything else just works off our
    /// own `WeatherCondition`, so WeatherKit's specifics never leak past this point.
    init(weatherKitCondition: WeatherKit.WeatherCondition) {
        switch weatherKitCondition {
        case .clear, .mostlyClear, .hot:
            self = .clear

        case .partlyCloudy:
            self = .partlyCloudy

        case .cloudy, .mostlyCloudy, .haze, .smoky, .blowingDust,
             .breezy, .windy, .frigid:
            self = .cloudy

        case .drizzle, .rain, .heavyRain, .freezingDrizzle, .freezingRain,
             .sunShowers, .isolatedThunderstorms, .scatteredThunderstorms:
            self = .rain

        case .thunderstorms, .strongStorms, .hurricane, .tropicalStorm:
            self = .storm

        case .snow, .flurries, .heavySnow, .blowingSnow, .blizzard,
             .sunFlurries, .wintryMix, .sleet, .hail:
            self = .snow

        case .foggy:
            self = .fog

        @unknown default:
            self = .cloudy
        }
    }
}
