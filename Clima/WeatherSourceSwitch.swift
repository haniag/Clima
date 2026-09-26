//
//  WeatherSourceSwitch.swift
//  Clima
//

import Foundation

/// Decides which weather service answers: WeatherKit, or the new one. A triple-tap on the
/// dial's current icon swaps between them.
///
/// It's a `WeatherProviding` itself, handing each fetch to whichever service is current,
/// so the screen keeps talking to one object and never has to know there are two.
///
/// The choice lives in `UserDefaults`, so it survives quitting, relaunching and updating,
/// until it's triple-tapped back or the app is deleted.
final class WeatherSourceSwitch: WeatherProviding {

    /// The `UserDefaults` key. The screen writes it (through `@AppStorage`) and this reads
    /// it — one name, so the two can't drift apart.
    static let usesNewServiceKey = "usesNewWeatherService"

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

    /// Read on every fetch rather than once at launch, so the fetch the triple-tap starts
    /// already goes to the new service.
    ///
    /// The hourly strip's gaps are filled from that service's cache on the way out. Done
    /// here, once, rather than in each service, so the two can't handle it differently.
    func currentWeather() async throws -> WeatherSnapshot {
        let usesNewService = UserDefaults.standard.bool(forKey: Self.usesNewServiceKey)
        var snapshot = usesNewService
            ? try await newService.currentWeather()
            : try await weatherKit.currentWeather()
        let cache = usesNewService ? newServiceHours : weatherKitHours
        snapshot.hourly = cache.filling(snapshot.hourly)
        return snapshot
    }
}
