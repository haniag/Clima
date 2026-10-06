//
//  LocationNameService.swift
//  Clima
//

import CoreLocation
import Foundation

/// Looks up what the place the phone is in is called — "Centreville" — for the header.
///
/// Shared by both weather services, since the name doesn't depend on which one is giving
/// the weather. Views never call this directly; the name reaches the screen on
/// `WeatherSnapshot.locationName`, the same way everything else does.
nonisolated enum LocationNameService {

    /// The location endpoint, path included — for example
    /// `URL(string: "https://example.com/location/point")`. The query string is added below.
    ///
    /// Still to be decided, so it's nil for now, and the header keeps saying "Clima".
    //static let endpointURL: URL? = nil
    static let endpointURL: URL? = URL(string: "https://weather.com/api/location/canonical")

    /// The place's name, or nil if the endpoint isn't set or the lookup fails for any
    /// reason.
    ///
    /// Never throws: the name is a nicety, and a good weather reading shouldn't be thrown
    /// away because the header couldn't be labelled. A failure goes to the console instead.
    static func name(for location: CLLocation) async -> String? {
        guard let endpointURL, let url = requestURL(endpoint: endpointURL, location: location) else {
            return nil
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                print("Location name lookup failed: HTTP \(status)")
                return nil
            }
            let place = try JSONDecoder().decode(LocationResponse.self, from: data)
            return place.displayName ?? place.city
        } catch {
            print("Location name lookup failed: \(error)")
            return nil
        }
    }

    /// `…?geocode=38.84,-77.44&language=en-US`
    ///
    /// Two decimal places, the same as the weather requests: about a kilometre, which is
    /// plenty to name a town and coarser than someone's front door.
    private static func requestURL(endpoint: URL, location: CLLocation) -> URL? {
        let geocode = String(
            format: "%.2f,%.2f",
            location.coordinate.latitude,
            location.coordinate.longitude
        )
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "geocode", value: geocode),
            URLQueryItem(name: "language", value: "en-US"),
        ]
        return components?.url
    }
}

/// The parts of the location response the app reads. The response has around two dozen
/// fields; the decoder ignores any not listed here. Both are optional, so a response
/// missing one still decodes.
nonisolated private struct LocationResponse: Decodable {
    /// The short name — "Centreville".
    let displayName: String?
    /// Used only if `displayName` is missing.
    let city: String?
}
