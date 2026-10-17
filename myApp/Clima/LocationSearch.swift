//
//  LocationSearch.swift
//  Clima
//

import MapKit
import Observation

/// Suggests places as someone types, and turns the one they pick into a `ChosenPlace`.
///
/// Apple's own search (MapKit), so it needs no API key and no account — it's the
/// WeatherKit side's search. Views read `results` and call `resolve`; MapKit stops here.
@Observable
final class LocationSearch: NSObject {

    /// What's typed in the search field. Each change is handed straight to the completer,
    /// which answers through the delegate below — it does its own throttling, so there's
    /// no need for a delay of our own.
    var query = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                results = []
                isWaiting = false
            } else {
                isWaiting = true
                completer.queryFragment = trimmed
            }
        }
    }

    /// The suggestions for `query`, best first: "Paris" over "France", and so on.
    private(set) var results: [MKLocalSearchCompletion] = []

    /// True from a keystroke until the completer answers it, so the sheet doesn't say
    /// "No matches" about a search that simply hasn't come back yet.
    private(set) var isWaiting = false

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        // Towns, cities, regions and postcodes — the kinds of place that have weather.
        // Businesses and landmarks would only crowd them out.
        completer.resultTypes = .address
    }

    /// The suggestion's coordinates, looked up, as a place the weather can be fetched for.
    ///
    /// A suggestion is only text; finding where it is takes a second request. The name
    /// kept is the town where there is one, so the header reads "Paris" rather than the
    /// full "Paris, France" the suggestion was titled with.
    func resolve(_ completion: MKLocalSearchCompletion) async throws -> ChosenPlace {
        let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        guard let item = response.mapItems.first else {
            throw MKError(.placemarkNotFound)
        }
        let coordinate = item.placemark.coordinate
        return ChosenPlace(
            name: item.placemark.locality ?? item.name ?? completion.title,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZoneIdentifier: await timeZone(of: item)?.identifier,
            searchTitle: completion.title,
            searchSubtitle: completion.subtitle
        )
    }

    /// The place's time zone. The search result normally has it; when it doesn't, a
    /// reverse geocode of its coordinates is asked instead. Nil if neither knows, and the
    /// phone's own time zone is used.
    private func timeZone(of item: MKMapItem) async -> TimeZone? {
        if let timeZone = item.timeZone {
            return timeZone
        }
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
        )
        return placemarks?.first?.timeZone
    }
}

extension LocationSearch: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Cleared meanwhile: an answer for the old text mustn't fill the empty field.
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        results = completer.results
        isWaiting = false
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Usually just no network. The sheet says "No matches"; the details go to the log.
        print("Location search failed: \(error)")
        results = []
        isWaiting = false
    }
}
