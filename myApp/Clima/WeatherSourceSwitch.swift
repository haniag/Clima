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
        return snapshot
    }
}
