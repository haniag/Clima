//
//  NewWeatherService.swift
//  Clima
//

import CoreLocation
import Foundation

/// The new weather source — the default, and one of the two chosen between in Settings.
///
/// It stands in the same place `WeatherService` does — both are `WeatherProviding` — so
/// the screen can't tell them apart and nothing outside this file knows this API exists.
/// Its JSON, its icon codes and its query parameters all stop here, and what comes out
/// the other side is the same `WeatherSnapshot` WeatherKit produces.
///
/// It reads three endpoints: current conditions for the dial, a 15-day forecast for the
/// 7-day strip, and an hourly forecast for the hourly strip.
final class NewWeatherService: WeatherProviding {

    /// The current-conditions endpoint, including the `/current` path — for example
    /// `URL(string: "https://example.com/current")`. The query string is added below.
    ///
    /// Still to be decided, so it's nil for now, and a fetch reports "not set up" rather
    /// than sending a request anywhere.
    //static let currentConditionsURL: URL? = nil
    static let currentConditionsURL: URL? = URL(string: "https://api.weather.com/v3/wx/observations/current")
    
   
    /// The 15-day forecast endpoint, path included, the same way as above. It takes the
    /// same query string as current conditions.
    ///
    /// Also still to be decided. While it's nil the dial still works and the 7-day strip
    /// shows dashes, so current conditions can be tried out before this address is known.
    //static let dailyForecastURL: URL? = nil
    static let dailyForecastURL: URL? = URL(string: "https://api.weather.com/v3/wx/forecast/daily/15day")
    

    /// The hourly forecast endpoint, path included, with the same query string again.
    ///
    /// Also still to be decided. While it's nil the hourly strip shows dashes apart from
    /// the hour we're in, which shows the live reading.
    //static let hourlyForecastURL: URL? = nil
    static let hourlyForecastURL: URL? = URL(string: "https://api.weather.com/v3/wx/forecast/hourly/3day")
    
    


    private let locationProvider: LocationProvider

    /// Takes the location provider for the same reasons `WeatherService` does — see its
    /// initializer. The app passes in the one both services share.
    @MainActor
    init(locationProvider: LocationProvider? = nil) {
        self.locationProvider = locationProvider ?? LocationProvider()
    }

    func currentWeather() async throws -> WeatherSnapshot {
        try await withTimeout(WeatherService.timeout) { [self] in
            try await fetchSnapshot()
        }
    }

    private func fetchSnapshot() async throws -> WeatherSnapshot {
        guard let endpoint = Self.currentConditionsURL, !Secrets.newWeatherAPIKey.isEmpty else {
            throw WeatherServiceError.notConfigured
        }

        let location = try await locationProvider.currentLocation()

        // All three requests go out at once, and the reading is only kept if all of them
        // succeed — the same all-or-nothing rule WeatherKit's single call gives, so the
        // dial never sits above a strip that failed to load.
        async let observationRequest = Self.get(CurrentObservation.self, from: endpoint, at: location)
        async let dailyRequest = Self.getIfSet(FifteenDayForecast.self, from: Self.dailyForecastURL, at: location)
        async let hourlyRequest = Self.getIfSet(HourlyForecastResponse.self, from: Self.hourlyForecastURL, at: location)
        // The place name goes out with them but isn't part of that rule — it can't fail,
        // only come back nil. See `LocationNameService`.
        async let locationName = LocationNameService.name(for: location)
        let (observation, forecast, hourly) = try await (observationRequest, dailyRequest, hourlyRequest)

        let condition = WeatherCondition(iconCode: observation.iconCode)
        let temperature = Int(observation.temperature.rounded())
        let fetchedAt = Date()

        return WeatherSnapshot(
            condition: condition,
            temperature: temperature,
            // The service's own words when it sent some; our label for the slot otherwise.
            conditionLabel: observation.wxPhraseShort ?? condition.label,
            humidity: observation.relativeHumidity.map { Int($0.rounded()) },
            precipitationLastHour: observation.precip1Hour,
            daily: forecast.map { Self.dailyForecasts(from: $0, today: fetchedAt) }
                ?? .placeholder(from: fetchedAt),
            hourly: Self.hourlyForecasts(from: hourly, now: (condition, temperature), at: fetchedAt),
            locationName: await locationName,
            fetchedAt: fetchedAt
        )
    }

    /// One request to one of the service's endpoints, decoded into `T`. Anything but a 200
    /// is a `badResponse`, and a body missing a required field fails to decode.
    private static func get<T: Decodable>(_ type: T.Type, from endpoint: URL, at location: CLLocation) async throws -> T {
        let url = try requestURL(endpoint: endpoint, location: location)
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw WeatherServiceError.badResponse(status: status)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// `get`, for the forecast endpoints: nil without asking when the address isn't set yet.
    private static func getIfSet<T: Decodable>(_ type: T.Type, from endpoint: URL?, at location: CLLocation) async throws -> T? {
        guard let endpoint else { return nil }
        return try await get(T.self, from: endpoint, at: location)
    }

    /// Today and the six days after it, matched out of the 15-day forecast by date.
    ///
    /// Slot-first, the same as WeatherKit's strip: the forecast starts at today, but only
    /// matching by date makes sure one day's weather never lands under another day's
    /// letter. A day the forecast doesn't cover shows dashes in its own column.
    ///
    /// Icon and precipitation come from the forecast's day/night pairs — entry `2 × day`
    /// is that day's daytime, `2 × day + 1` its night. The column uses the daytime value,
    /// and falls back to the night only when the daytime is missing, which is how the
    /// service reports today once the day part is over.
    ///
    /// The one exception is today after its sunset: the day is over as far as anyone
    /// looking at the sky is concerned, so today's column shows the night's icon, moon
    /// and all.
    private static func dailyForecasts(from forecast: FifteenDayForecast, today: Date) -> [DailyForecast] {
        let calendar = Calendar.current
        let start = [DailyForecast].stripStart(containing: today)
        let parts = forecast.daypart.first

        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            guard let index = forecast.validTimeUtc.firstIndex(where: {
                calendar.isDate(Date(timeIntervalSince1970: $0), inSameDayAs: date)
            }) else {
                return DailyForecast(
                    date: date, condition: nil, highTemp: nil, lowTemp: nil, precipitationChance: nil
                )
            }
            let precipChance = element(parts?.precipChance, 2 * index) ?? element(parts?.precipChance, 2 * index + 1)

            let condition: WeatherCondition?
            if offset == 0, let sunset = sunset(from: forecast, at: index), today >= sunset {
                // Night first, and left as a night condition. The daytime value is only
                // a fallback, in case the service hasn't sent tonight's.
                condition = (element(parts?.iconCode, 2 * index + 1) ?? element(parts?.iconCode, 2 * index))
                    .map { WeatherCondition(iconCode: $0) }
            } else {
                condition = (element(parts?.iconCode, 2 * index) ?? element(parts?.iconCode, 2 * index + 1))
                    .map { daytime(WeatherCondition(iconCode: $0)) }
            }

            return DailyForecast(
                date: date,
                condition: condition,
                highTemp: element(forecast.temperatureMax, index).map { Int($0.rounded()) },
                lowTemp: element(forecast.temperatureMin, index).map { Int($0.rounded()) },
                precipitationChance: precipChance.map { Int($0.rounded()) }
            )
        }
    }

    /// `array[index]`, or nil when the array is missing, too short, or holds a null there.
    private static func element<T>(_ array: [T?]?, _ index: Int) -> T? {
        guard let array, array.indices.contains(index) else { return nil }
        return array[index]
    }

    /// The day at `index`'s sunset, from `sunsetTimeLocal` — e.g.
    /// `"2026-09-25T19:03:12-0400"`. The string carries its own UTC offset, so it names
    /// the same moment whatever time zone the phone is set to. Nil when the service
    /// didn't send one or it doesn't parse, in which case the column stays on daytime.
    private static func sunset(from forecast: FifteenDayForecast, at index: Int) -> Date? {
        element(forecast.sunsetTimeLocal, index).flatMap { sunsetFormatter.date(from: $0) }
    }

    private static let sunsetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // POSIX so the phone's own region and 12/24-hour setting can't change how the
        // string is read.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()

    /// The daytime version of a condition. The strip doesn't show a moon — a column is a
    /// whole day — so a night icon code borrowed for today evening gets its sun back.
    /// (Today after sunset is the exception; see `dailyForecasts`.)
    private static func daytime(_ condition: WeatherCondition) -> WeatherCondition {
        switch condition {
        case .clearNight: return .clear
        case .partlyCloudyNight: return .partlyCloudy
        default: return condition
        }
    }

    /// `…/current?geocode=38.85,-77.30&units=e&language=en-US&format=json&apiKey=…`
    ///
    /// The location goes to two decimal places — about a kilometre, which is finer than
    /// the weather varies over and coarser than someone's front door.
    private static func requestURL(endpoint: URL, location: CLLocation) throws -> URL {
        let geocode = String(
            format: "%.2f,%.2f",
            location.coordinate.latitude,
            location.coordinate.longitude
        )
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "geocode", value: geocode),
            // "e" is imperial: Fahrenheit, which is the unit the whole app stores.
            URLQueryItem(name: "units", value: "e"),
            URLQueryItem(name: "language", value: "en-US"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "apiKey", value: Secrets.newWeatherAPIKey),
        ]
        guard let url = components?.url else {
            throw WeatherServiceError.notConfigured
        }
        return url
    }

    /// The current hour through the midnight that ends tomorrow, each filled from the
    /// forecast for that hour.
    ///
    /// The hour we're in shows the live reading instead — same rule as WeatherKit's
    /// strip: the "now" column never disagrees with the dial above it.
    ///
    /// Reaching the end of tomorrow takes up to 48 hours of forecast, so the endpoint
    /// needs to be one that covers two days. Every hour shows dashes while the endpoint
    /// isn't set, apart from what `HourlyCache` has.
    private static func hourlyForecasts(
        from forecast: HourlyForecastResponse?,
        now: (condition: WeatherCondition, temperature: Int),
        at date: Date
    ) -> [HourlyForecast] {
        let calendar = Calendar.current
        return [HourlyForecast].placeholder(from: date).map { slot in
            // Matched by time rather than position, for the same reason as the days.
            let index = forecast?.validTimeUtc.firstIndex(where: {
                calendar.isDate(Date(timeIntervalSince1970: $0), equalTo: slot.date, toGranularity: .hour)
            })
            let precipChance = index
                .flatMap { element(forecast?.precipChance, $0) }
                .map { Int($0.rounded()) }

            // The live reading has no chance of precipitation, so the current hour still
            // takes that one from the forecast.
            if slot.contains(date) {
                return HourlyForecast(
                    date: slot.date,
                    condition: now.condition,
                    temperature: now.temperature,
                    precipitationChance: precipChance
                )
            }
            guard let forecast, let index else {
                return slot
            }
            return HourlyForecast(
                date: slot.date,
                // Night codes keep their moon here: an hour, unlike a day, is either one.
                condition: element(forecast.iconCode, index).map { WeatherCondition(iconCode: $0) },
                temperature: element(forecast.temperature, index).map { Int($0.rounded()) },
                precipitationChance: precipChance
            )
        }
    }
}

/// The parts of the current-conditions response the app reads. The response has around
/// fifty fields; the decoder ignores any not listed here.
///
/// `temperature` and `iconCode` are required: a reading without them has nothing to put on
/// the dial, so decoding fails and the screen shows its usual "couldn't get the weather"
/// line. Humidity, precipitation and the phrase are optional — the readout manages
/// without any of them.
///
/// `nonisolated`, like the two forecast types below, because the project puts types on the
/// main actor by default and all three responses are decoded off it, in the concurrent
/// requests.
nonisolated private struct CurrentObservation: Decodable {
    let iconCode: Int
    /// Degrees Fahrenheit, because the request asks for `units=e`. A `Double` so a
    /// decimal reading decodes too; it's rounded to a whole degree on the way out.
    let temperature: Double
    let relativeHumidity: Double?
    /// Inches in the last hour, because the request asks for `units=e`.
    let precip1Hour: Double?
    let wxPhraseShort: String?
}

/// The parts of the 15-day forecast response the app reads.
///
/// Every field is a list with one entry per day, the first being today. Entries are
/// optional because the service sends `null` for ones that no longer apply — today's high
/// and daytime values, for instance, once the day part is over. A null becomes a dash in
/// that column rather than failing the whole forecast.
nonisolated private struct FifteenDayForecast: Decodable {
    /// Each day's start as seconds since 1970; used to match days to the strip's columns.
    let validTimeUtc: [TimeInterval]
    /// Degrees Fahrenheit, because the request asks for `units=e`.
    let temperatureMax: [Double?]
    let temperatureMin: [Double?]
    /// Each day's sunset as local time with its UTC offset, e.g. `"2026-09-25T19:03:12-0400"`.
    /// Optional as a whole, so a response without it still decodes; the strip just
    /// doesn't switch today to night.
    let sunsetTimeLocal: [String?]?
    /// The service sends this as a list holding one object.
    let daypart: [DayParts]

    /// Twice as long as the lists above: each day's daytime entry, then its night.
    struct DayParts: Decodable {
        let iconCode: [Int?]?
        /// Whole percent, 0–100.
        let precipChance: [Double?]?
    }
}

/// The parts of the hourly forecast response the app reads: one entry per hour, the first
/// being the current hour. Optional entries for the same reason as `FifteenDayForecast`'s.
nonisolated private struct HourlyForecastResponse: Decodable {
    /// Each hour's start as seconds since 1970; used to match hours to the strip's columns.
    let validTimeUtc: [TimeInterval]
    /// Degrees Fahrenheit, because the request asks for `units=e`.
    let temperature: [Double?]
    let iconCode: [Int?]
    /// Whole percent, 0–100. Optional as a whole, so a response without it still decodes
    /// and the row just shows dashes.
    let precipChance: [Double?]?
}
