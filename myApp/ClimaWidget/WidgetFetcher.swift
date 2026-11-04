//
//  WidgetFetcher.swift
//  ClimaWidget
//

import Foundation

/// The widget's own fetch, so it stays current without the app being opened.
///
/// It goes through the app's own weather services — the same files, compiled into the
/// widget too — so it asks the same source for the same place in the same way, and
/// WeatherKit and the new service's endpoints still only appear in those files.
///
/// `@MainActor` because `LocationProvider` has to be built on the main thread, the same
/// as in the app.
@MainActor
enum WidgetFetcher {

    /// Fetches a fresh reading and saves it for the next timeline, or returns nil if
    /// the fetch fails — the caller falls back on what's already saved.
    ///
    /// The source comes from what the app last saved, since the Settings app's choice
    /// can't be read from here. With nothing saved yet, it's the app's default.
    static func refreshed() async -> WidgetWeather? {
        let source = WidgetWeather.saved?.source.flatMap(WeatherSource.init(rawValue:)) ?? .default
        let locationProvider = LocationProvider()
        let service: WeatherProviding = source == .weatherKit
            ? WeatherService(locationProvider: locationProvider)
            : NewWeatherService(locationProvider: locationProvider)

        do {
            let snapshot = try await service.currentWeather()
            // Read after the fetch rather than before, so a °F/°C flip the app saved while
            // this was out isn't overwritten with the old setting.
            let useCelsius = WidgetWeather.saved?.useCelsius ?? false
            let weather = WidgetWeather(snapshot, useCelsius: useCelsius, source: source)
            WidgetWeather.saved = weather
            return weather
        } catch {
            // Most often location: the app hasn't been given permission yet, or the
            // phone couldn't get a fix in time.
            print("Widget fetch failed: \(error)")
            return nil
        }
    }
}
