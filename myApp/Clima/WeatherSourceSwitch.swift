//
//  WeatherSourceSwitch.swift
//  Clima
//

import Foundation

/// The weather services the app can read from.
///
/// The raw values are what's stored in `UserDefaults`, and they must match the `Values`
/// list in `Settings.bundle/Root.plist`, which is where the choice is made.
enum WeatherSource: String {
    case newService
    case weatherKit

    /// The `UserDefaults` key — the same one the Settings page writes to.
    static let key = "weatherSource"

    /// What the app uses until the setting is changed. Must match `DefaultValue` in
    /// `Settings.bundle/Root.plist`: iOS only uses that one to draw the Settings page,
    /// and never stores it for the app to read.
    static let `default`: WeatherSource = .newService

    /// The choice as it stands, read fresh each time.
    static var current: WeatherSource {
        UserDefaults.standard.string(forKey: key).flatMap(WeatherSource.init(rawValue:)) ?? .default
    }

    /// Writes the default into `UserDefaults` when nothing usable is stored there, so the
    /// Settings page has a value to put its checkmark on. Settings can't be relied on to
    /// tick `DefaultValue` by itself — until the app stores something, the list can show
    /// with no option ticked. Also replaces a stored value that matches no option, such
    /// as "Weather Channel" from an earlier build whose Settings page saved the label
    /// instead of the raw value. Called once at launch.
    static func saveDefaultIfMissing() {
        let stored = UserDefaults.standard.string(forKey: key)
        if stored.flatMap(WeatherSource.init(rawValue:)) == nil {
            UserDefaults.standard.set(WeatherSource.default.rawValue, forKey: key)
        }
    }
}

/// Decides which weather service answers: the new one, or WeatherKit. The choice is made
/// on the app's page in the iPhone's Settings app.
///
/// It's a `WeatherProviding` itself, handing each fetch to whichever service is current,
/// so the screen keeps talking to one object and never has to know there are two.
final class WeatherSourceSwitch: WeatherProviding {

    private let weatherKit: WeatherProviding
    private let newService: WeatherProviding

    /// One per service — see `HourlyCache` for why they're kept apart.
    private let weatherKitHours = HourlyCache(source: "weatherKit")
    private let newServiceHours = HourlyCache(source: "newService")

    /// Builds both services around ONE location provider, so they share its permission
    /// state and the Simulator's geocoded ZIP rather than each keeping its own.
    @MainActor
    init() {
        let locationProvider = LocationProvider()
        weatherKit = WeatherService(locationProvider: locationProvider)
        newService = NewWeatherService(locationProvider: locationProvider)
    }

    /// Read on every fetch rather than once at launch, so a change made in Settings
    /// applies to the very next fetch.
    ///
    /// The hourly strip's gaps are filled from that service's cache on the way out. Done
    /// here, once, rather than in each service, so the two can't handle it differently.
    func currentWeather() async throws -> WeatherSnapshot {
        let source = WeatherSource.current
        var snapshot = source == .newService
            ? try await newService.currentWeather()
            : try await weatherKit.currentWeather()
        let cache = source == .newService ? newServiceHours : weatherKitHours
        snapshot.hourly = cache.filling(snapshot.hourly)
        Self.save(snapshot, from: source)
        return snapshot
    }

    // MARK: - The reading kept for the next launch

    /// The last reading fetched, if it's still worth opening on: from the service and for
    /// the place that are chosen now, and from today.
    ///
    /// "Today" is counted where the weather is for, because the 7-day strip is. A reading
    /// from yesterday would open with yesterday in the column that's always today, and a
    /// page of dashes is more honest than that.
    var savedWeather: WeatherSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: Self.savedKey),
              // Something that no longer decodes (after an app update changed the
              // reading's shape, say) counts as nothing saved, rather than an error.
              let saved = try? JSONDecoder().decode(SavedReading.self, from: data),
              saved.source == WeatherSource.current.rawValue,
              saved.place == ChosenPlace.saved,
              Calendar.local(to: saved.snapshot.timeZone).isDateInToday(saved.snapshot.fetchedAt)
        else { return nil }
        return saved.snapshot
    }

    /// A reading, with which service it came from and which place it's for — `nil` being
    /// the phone's own location — so it's only ever shown again for the same two.
    private struct SavedReading: Codable {
        let source: String
        let place: ChosenPlace?
        let snapshot: WeatherSnapshot
    }

    private static let savedKey = "savedReading"

    /// Kept in `UserDefaults`, like `HourlyCache`: one small value that should outlive
    /// quitting the app. A failure to save costs the next launch its head start and
    /// nothing else.
    private static func save(_ snapshot: WeatherSnapshot, from source: WeatherSource) {
        let reading = SavedReading(source: source.rawValue, place: ChosenPlace.saved, snapshot: snapshot)
        guard let data = try? JSONEncoder().encode(reading) else { return }
        UserDefaults.standard.set(data, forKey: savedKey)
    }
}
