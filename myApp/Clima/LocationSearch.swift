//
//  LocationSearch.swift
//  Clima
//

import MapKit
import Observation

/// One line in the search sheet's results.
///
/// The two searches answer differently: a MapKit suggestion is only text and needs a
/// second lookup to find where it is, while the new service's answer already is a place.
/// Both end up here, so the sheet lists them the same way.
struct PlaceSuggestion: Hashable, Identifiable {
    enum Source: Hashable {
        /// From MapKit; `LocationSearch.resolve` looks up its coordinates.
        case mapKit(MKLocalSearchCompletion)
        /// From the new service, coordinates and all.
        case found(ChosenPlace)
    }

    let title: String
    let subtitle: String?
    let source: Source

    var id: Self { self }
}

/// Suggests places as someone types, and turns the one they pick into a `ChosenPlace`.
///
/// Searches the same service the weather comes from: Apple's own (MapKit) for WeatherKit,
/// and the new service's location search (`FindLocationService`) for it. Views read
/// `results` and call `resolve`; neither search is seen past here.
@Observable
final class LocationSearch: NSObject {

    /// What's typed in the search field. Each change starts a new search.
    var query = "" {
        didSet { search(query.trimmingCharacters(in: .whitespaces)) }
    }

    /// The suggestions for `query`, best first: "Paris" over "France", and so on.
    private(set) var results: [PlaceSuggestion] = []

    /// True from a keystroke until the search answers it, so the sheet doesn't say
    /// "No matches" about a search that simply hasn't come back yet.
    private(set) var isWaiting = false

    /// Set when the search itself can't be done — not set up yet, or no network — so the
    /// sheet can say so rather than "No matches". Nil otherwise.
    private(set) var problem: String?

    @ObservationIgnored private let source: WeatherSource
    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    /// The new service's search in flight, cancelled when another keystroke replaces it.
    @ObservationIgnored private var findTask: Task<Void, Never>?

    init(source: WeatherSource) {
        self.source = source
        super.init()
        completer.delegate = self
        // Towns, cities, regions and postcodes — the kinds of place that have weather.
        // Businesses and landmarks would only crowd them out.
        completer.resultTypes = .address
    }

    private func search(_ text: String) {
        findTask?.cancel()
        problem = nil
        guard !text.isEmpty else {
            results = []
            isWaiting = false
            return
        }
        isWaiting = true
        switch source {
        case .weatherKit:
            // MapKit throttles itself and answers through the delegate below.
            completer.queryFragment = text
        case .newService:
            findTask = Task { await find(text) }
        }
    }

    /// One search on the new service.
    ///
    /// Waits a moment first, and is cancelled if another keystroke comes in meanwhile: the
    /// service, unlike MapKit, doesn't throttle itself, and typing "Paris" shouldn't send
    /// five requests.
    private func find(_ text: String) async {
        do {
            try await Task.sleep(for: .milliseconds(300))
            let places = try await FindLocationService.places(matching: text)
            try Task.checkCancellation()
            results = places.map { place in
                PlaceSuggestion(title: place.searchTitle ?? place.name, subtitle: place.searchSubtitle,
                                source: .found(place))
            }
        } catch is CancellationError {
            // Replaced by a newer keystroke, which will answer instead.
            return
        } catch {
            print("Location search failed: \(error)")
            results = []
            if case .notConfigured? = error as? WeatherServiceError {
                problem = "Location search isn't set up yet."
            } else {
                problem = "Couldn't search right now. Try again in a moment."
            }
        }
        isWaiting = false
    }

    /// The suggestion as a place the weather can be fetched for.
    ///
    /// The new service's suggestions already are one. A MapKit suggestion is only text,
    /// so finding where it is takes a second request. The name kept is the town where
    /// there is one, so the header reads "Paris" rather than the full "Paris, France" the
    /// suggestion was titled with.
    func resolve(_ suggestion: PlaceSuggestion) async throws -> ChosenPlace {
        let completion: MKLocalSearchCompletion
        switch suggestion.source {
        case .found(let place):
            return place
        case .mapKit(let mapKitCompletion):
            completion = mapKitCompletion
        }

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
        results = completer.results.map {
            PlaceSuggestion(title: $0.title, subtitle: $0.subtitle, source: .mapKit($0))
        }
        isWaiting = false
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Location search failed: \(error)")
        results = []
        // MapKit reports "no results" as an error too; that one is just "No matches".
        if (error as? MKError)?.code != .placemarkNotFound {
            problem = "Couldn't search right now. Try again in a moment."
        }
        isWaiting = false
    }
}
