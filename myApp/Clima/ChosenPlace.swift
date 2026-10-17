//
//  ChosenPlace.swift
//  Clima
//

import CoreLocation
import Foundation

/// A place picked from the location search, to show the weather for instead of wherever
/// the phone is.
///
/// Nil — nothing saved — means "my current location", which is where the app starts.
/// Kept in `UserDefaults`, so the choice survives quitting the app: someone following the
/// weather somewhere else shouldn't have to pick it again every launch.
///
/// `nonisolated` because the project puts types on the main actor by default, and the
/// weather services read this from off it.
nonisolated struct ChosenPlace: Codable, Hashable {
    /// What the header calls it — "Paris".
    let name: String
    let latitude: Double
    let longitude: Double
    /// The place's time zone, e.g. "Europe/Paris", so its hours and days can be shown as
    /// its own clocks read them. Optional so a place saved before this was added still
    /// decodes; such a place falls back to the phone's time zone until it's picked again.
    let timeZoneIdentifier: String?
    /// How the search listed it — "Paris, TX" over "United States" — so the recent places
    /// in the sheet can tell one Paris from another, where the header's `name` is just
    /// "Paris". Optional for the same reason as the time zone; the list falls back to
    /// `name`.
    var searchTitle: String? = nil
    var searchSubtitle: String? = nil

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var timeZone: TimeZone? {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    private static let key = "chosenPlace"

    /// The place chosen in the search sheet, or nil for the current location.
    static var saved: ChosenPlace? {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            // Something that no longer decodes counts as no choice, rather than an error.
            return try? JSONDecoder().decode(ChosenPlace.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// Makes `place` the choice, or the current location if it's nil — and, for a place,
    /// puts it at the top of `recents`.
    static func choose(_ place: ChosenPlace?) {
        saved = place
        guard let place else { return }
        recents = [place] + recents.filter { !$0.isSame(as: place) }
    }

    // MARK: - Recent places

    /// How many recent places the sheet lists.
    static let recentsLimit = 5

    private static let recentsKey = "recentPlaces"

    /// The places chosen most recently, newest first, each once, at most `recentsLimit`.
    /// Shown in the search sheet so going back to one doesn't need another search.
    static var recents: [ChosenPlace] {
        get {
            guard let data = UserDefaults.standard.data(forKey: recentsKey) else { return [] }
            return (try? JSONDecoder().decode([ChosenPlace].self, from: data)) ?? []
        }
        set {
            let kept = Array(newValue.prefix(recentsLimit))
            guard let data = try? JSONEncoder().encode(kept) else { return }
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }

    /// Whether two picks are the same place: within a kilometre of each other. Picking
    /// Paris twice can come back with coordinates a few metres apart, and that mustn't
    /// list Paris twice.
    func isSame(as other: ChosenPlace) -> Bool {
        location.distance(from: other.location) < 1_000
    }
}
