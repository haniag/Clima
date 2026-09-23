//
//  WeatherErrorMessage.swift
//  Clima
//

import CoreLocation
import Foundation
import os

/// Turns whatever a failed fetch threw into a sentence worth putting on screen.
///
/// The rule this exists to enforce: **the reader never sees an error's own wording.**
/// Left to itself, `localizedDescription` produced
/// *"The operation couldn't be completed. (WeatherDaemon.WDSJWTAuthenticatorService
/// Listener.Errors error 2.)"* — three lines of internal vocabulary that tells someone
/// holding a phone nothing they can act on, and tells the person maintaining the app
/// nothing either, because it's on screen rather than in a log where it can be searched.
///
/// So the two audiences are served separately: a plain sentence goes to the screen, and
/// the raw error goes to the console via `Logger`. Both come out of the same call, so
/// they can't drift apart.
enum WeatherErrorMessage {

    private static let log = Logger(subsystem: "com.fursa.Clima", category: "weather")

    /// What to show, having first recorded what actually happened.
    static func text(for error: Error) -> String {
        // The full error, once, where a developer can find it — `privacy: .public`
        // because none of this is the user's data and a redacted log is no use.
        log.error("Weather fetch failed: \(String(describing: error), privacy: .public)")

        // Our own failures already carry wording written for a reader — that's what their
        // `errorDescription` is for — so they pass straight through.
        if let locationError = error as? LocationProvider.LocationError {
            return locationError.errorDescription ?? generic
        }
        if let serviceError = error as? WeatherServiceError {
            return serviceError.errorDescription ?? generic
        }

        // CoreLocation reports through `CLError`, not through our enum, whenever the
        // failure came from the system rather than from our own checks — Location Services
        // switched off for the whole device, a geocode with no network behind it, a fix
        // that never resolved. Without this they all fell through to the generic sentence,
        // which is the least useful answer for the most actionable class of problem.
        if let locationError = error as? CLError {
            switch locationError.code {
            case .denied:
                return LocationProvider.LocationError.permissionDenied.errorDescription ?? generic
            case .network:
                return "No internet connection. Tap the hub to try again once you're back online."
            case .locationUnknown, .geocodeFoundNoResult, .geocodeFoundPartialResult:
                return LocationProvider.LocationError.noFix.errorDescription ?? generic
            default:
                return generic
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "No internet connection. Tap the hub to try again once you're back online."
            case .timedOut:
                return "The weather service took too long to answer. Tap the hub to try again."
            default:
                return "Couldn't reach the weather service. Tap the hub to try again."
            }
        }

        // Everything WeatherKit itself throws lands here. Its errors are a private
        // vocabulary — the authentication failure above doesn't even have a public type
        // to match on — so rather than guess at a cause and risk naming the wrong one,
        // this says the true thing and points at the one control that retries.
        return generic
    }

    private static let generic = "Couldn't get the weather right now. Tap the hub to try again."
}
