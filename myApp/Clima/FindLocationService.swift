//
//  FindLocationService.swift
//  Clima
//

import Foundation

/// Finds places by name or postcode on the new weather service — its side of the location
/// search, the way MapKit is WeatherKit's.
///
/// Each answer already carries the place's coordinates and time zone, so unlike a MapKit
/// suggestion it needs no second lookup once picked. Its JSON stops here; what comes out
/// is `ChosenPlace`s.
nonisolated enum FindLocationService {

    /// The search endpoint, path included. The query string is added below.
    ///
    /// Still to be decided, so it's nil for now, and a search reports "not set up" rather
    /// than sending a request anywhere.
    static let endpointURL: URL? = URL(string: "https://api.weather.com/v3/location/search")

    /// What the search is narrowed to: places that have weather of their own, not
    /// businesses or points of interest.
    private static let locationTypes = "city,locality,neighborhood,postal,airport,address"

    /// The places matching `query`, best first. Empty when nothing matches.
    ///
    /// Throws `WeatherServiceError.notConfigured` while the endpoint or API key isn't set,
    /// and `badResponse` for an HTTP error.
    static func places(matching query: String) async throws -> [ChosenPlace] {
        guard let endpointURL, !Secrets.newWeatherAPIKey.isEmpty else {
            throw WeatherServiceError.notConfigured
        }
        var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "language", value: "en-US"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "apiKey", value: Secrets.newWeatherAPIKey),
            URLQueryItem(name: "locationType", value: locationTypes),
        ]
        guard let url = components?.url else {
            throw WeatherServiceError.notConfigured
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // The service answers a search with no matches with a 404 rather than an empty
        // list. That's "nothing found", not a failure.
        if status == 404 || status == 204 {
            return []
        }
        guard status == 200 else {
            throw WeatherServiceError.badResponse(status: status)
        }
        return try JSONDecoder().decode(FindLocationResponse.self, from: data).places
    }
}

/// The parts of the search response the app reads.
///
/// The response is one `location` object of parallel lists: entry 0 of every list is the
/// first match, entry 1 the second, and so on. Entries are optional because the service
/// sends `null` for ones that don't apply.
nonisolated private struct FindLocationResponse: Decodable {
    let location: Location

    struct Location: Decodable {
        /// The short name — "Fair Lakes".
        let displayName: [String?]?
        /// Where it is — "Fairfax, United States". Shown under the name in the sheet.
        let displayContext: [String?]?
        /// Used for the name only when `displayName` is missing.
        let city: [String?]?
        let latitude: [Double?]
        let longitude: [Double?]
        /// E.g. "America/New_York" — the place's own clock, for its hours and days.
        let ianaTimeZone: [String?]?
    }

    /// Every match with coordinates, in the order the service ranked them. A match
    /// without both coordinates can't be fetched for, so it's left out.
    var places: [ChosenPlace] {
        location.latitude.indices.compactMap { index in
            guard let latitude = element(location.latitude, index),
                  let longitude = element(location.longitude, index)
            else { return nil }
            let displayName = element(location.displayName, index)
            let name = displayName ?? element(location.city, index) ?? "Unknown place"
            return ChosenPlace(
                name: name,
                latitude: latitude,
                longitude: longitude,
                timeZoneIdentifier: element(location.ianaTimeZone, index),
                searchTitle: name,
                searchSubtitle: element(location.displayContext, index)
            )
        }
    }

    /// `array[index]`, or nil when the array is missing, too short, or holds a null there.
    private func element<T>(_ array: [T?]?, _ index: Int) -> T? {
        guard let array, array.indices.contains(index) else { return nil }
        return array[index]
    }
}
