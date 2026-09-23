//
//  LocationProvider.swift
//  Clima
//

import CoreLocation

/// Answers one question: where should we ask for the weather?
///
/// There are two answers, and which one you get depends on where the app is running:
///
/// - **On a real device** — the user's own location, which means asking their permission
///   first and waiting for a fix.
/// - **In the Simulator** — a fixed ZIP code. A simulated iPhone has no GPS. It reports
///   whatever Xcode's *Features ▸ Location* menu is set to, and that defaults to *None*,
///   which makes `requestLocation()` simply never call back — the dial would sit on its
///   loading state forever with nothing to show for it. A real place to look up is far
///   more useful during development than a fix that never arrives.
///
/// Both paths are compiled into every build, and `isSimulator` picks between them at
/// run time. The obvious alternative — wrapping each path in `#if
/// targetEnvironment(simulator)` — would mean the device path never gets compiled while
/// we're working in the Simulator, so a typo in it wouldn't surface until the first run
/// on real hardware. A constant costs nothing and keeps the compiler checking both.
///
/// **`@MainActor` is load-bearing, not decoration.** `CLLocationManager` delivers its
/// callbacks on the queue it was created on — the main queue here — while the methods
/// below are reached through `WeatherService`, whose `async` methods are *not* isolated
/// to any actor and therefore run on a background thread. That left `locationWaiters`
/// being appended to off the main thread while the delegate read and emptied it on the
/// main thread: an unsynchronized mutation of a Swift `Array`, which is undefined
/// behaviour, and one that can silently drop the waiter so its caller is never resumed.
/// It could only ever bite on a real device, since the Simulator takes the geocode path
/// and never touches `CLLocationManager` at all. Pinning the whole type to the main actor
/// puts the callers and the callbacks back on the same thread.
@MainActor
final class LocationProvider: NSObject {

    /// The ZIP the Simulator stands in for: Fairfax, Virginia. Geocoded on first use, so
    /// moving the Simulator somewhere else means changing this one string and nothing
    /// else.
    static let simulatorPostalCode = "22033"

    /// True when this build is running on a simulated device. See the note on the type
    /// above for why this is a constant rather than an `#if` around each call site.
    static let isSimulator: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()

    /// Why a location couldn't be produced.
    ///
    /// Only the failures the caller can actually do something about get their own case —
    /// a refused permission needs a trip to Settings, a missed fix just needs another
    /// try. Anything else is CoreLocation's own error, passed along untouched rather
    /// than flattened into a vague one of ours.
    enum LocationError: LocalizedError {
        case permissionDenied
        case noFix
        case postalCodeNotFound(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Clima needs your location to show local weather. Turn it back on in Settings ▸ Privacy & Security ▸ Location Services."
            case .noFix:
                return "Couldn't work out where you are. Try again in a moment."
            case .postalCodeNotFound(let code):
                return "Couldn't find ZIP code \(code)."
            }
        }
    }

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    /// The last authorization status CoreLocation reported.
    ///
    /// Cached rather than read back from the manager on every use, because
    /// `CLLocationManager.authorizationStatus` is a cross-process call — and now that this
    /// type is bound to the main actor, that call lands on the main thread. Xcode's
    /// Performance Diagnostics flags it by name: *"Interprocess communication on the main
    /// thread can cause non-deterministic delays"*, antipattern trigger
    /// `-[CLLocationManager authorizationStatus]`. The old code read it four times per
    /// fetch (once to decide, three more inside the delegate), all on the main thread.
    /// Read once at construction and kept current by the delegate, a refresh now costs
    /// none at all.
    private var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// The Simulator's geocoded ZIP, kept after the first lookup. Geocoding is a
    /// rate-limited network call, and the answer for a fixed ZIP can't change between one
    /// refresh and the next, so asking once a launch is both quicker and better mannered
    /// than asking every time the hub is tapped.
    private var cachedSimulatorLocation: CLLocation?

    /// The geocode currently in flight, if any.
    ///
    /// A `CLGeocoder` handles one request at a time and CANCELS the previous one when a
    /// second arrives — so two taps of the hub before the first answer came back left one
    /// caller holding a spurious "geocode cancelled" error. Sharing the one task means
    /// the second caller waits on the first answer instead of starting a race with it.
    private var simulatorLookup: Task<CLLocation, Error>?

    /// Everyone waiting on an answer, held so the delegate callbacks at the bottom of this
    /// file have something to resume.
    ///
    /// Arrays rather than single slots, because these used to be exactly that, and a
    /// second request arriving before the first was answered simply overwrote it — the
    /// first continuation was then never resumed, which hangs its caller forever and trips
    /// Swift's "continuation misuse" check. The hub can be tapped as fast as a finger
    /// moves, so that was reachable. Now every waiter is queued and every waiter gets the
    /// one answer CoreLocation sends back.
    ///
    /// Both are emptied the instant they're resumed. Resuming a continuation twice is a
    /// crash, not a warning, and CoreLocation is quite willing to call the same delegate
    /// method more than once for a single request.
    private var authorizationWaiters: [CheckedContinuation<Void, Error>] = []
    private var locationWaiters: [CheckedContinuation<CLLocation, Error>] = []

    override init() {
        super.init()
        manager.delegate = self
        // Street-level accuracy would be wasted: the dial shows one condition and one
        // temperature, neither of which changes across a few kilometres. The coarser
        // setting returns a fix sooner and costs much less battery.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        // The one read of the real thing, at launch. Everything after this comes from the
        // delegate, which is told whenever it changes.
        authorizationStatus = manager.authorizationStatus
    }

    /// Where to ask for weather, waiting on the user's permission if this is the first
    /// time and we're on real hardware.
    func currentLocation() async throws -> CLLocation {
        if Self.isSimulator {
            return try await simulatorLocation()
        }
        try await requestPermissionIfNeeded()
        return try await requestFix()
    }

    // MARK: - The Simulator's stand-in

    private func simulatorLocation() async throws -> CLLocation {
        if let cached = cachedSimulatorLocation {
            return cached
        }
        // Someone already asked and hasn't been answered yet — wait on their result
        // rather than starting a second geocode that would cancel theirs.
        if let lookup = simulatorLookup {
            return try await lookup.value
        }

        let lookup = Task<CLLocation, Error> { [geocoder] in
            // The country is spelled out because a bare five-digit string is ambiguous —
            // it reads as a house number or a partial address in plenty of places outside
            // the US.
            let placemarks = try await geocoder.geocodeAddressString("\(Self.simulatorPostalCode), USA")
            guard let location = placemarks.first?.location else {
                throw LocationError.postalCodeNotFound(Self.simulatorPostalCode)
            }
            return location
        }
        simulatorLookup = lookup

        do {
            let location = try await lookup.value
            cachedSimulatorLocation = location
            simulatorLookup = nil
            return location
        } catch {
            // Cleared on the way out either way, so a failed lookup doesn't wedge every
            // later attempt behind a task that will never succeed.
            simulatorLookup = nil
            throw error
        }
    }

    // MARK: - The real device

    private func requestPermissionIfNeeded() async throws {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return

        case .denied, .restricted:
            // Asking again here would do nothing: once the user has answered, iOS stops
            // showing the prompt and never calls the delegate back, so the await below
            // would hang rather than fail. Only Settings can change this now.
            throw LocationError.permissionDenied

        case .notDetermined:
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                authorizationWaiters.append(continuation)
                // Only the first waiter actually asks. iOS shows one prompt however many
                // times this is called, and the delegate below answers everybody.
                if authorizationWaiters.count == 1 {
                    manager.requestWhenInUseAuthorization()
                }
            }

        @unknown default:
            throw LocationError.permissionDenied
        }
    }

    private func requestFix() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationWaiters.append(continuation)
            // As above: one fix serves everyone waiting on one.
            if locationWaiters.count == 1 {
                manager.requestLocation()
            }
        }
    }
}

// MARK: - CoreLocation callbacks
//
// These arrive on the queue the manager was created on — the main queue, since that's
// where the app builds this object — so they can touch the continuations above directly.

extension LocationProvider: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Read once, into the cache, and use the cache from here on — see the note on
        // `authorizationStatus`. This is also what keeps that cache honest: it's the only
        // way to learn the user changed their mind in Settings while the app was away.
        let status = manager.authorizationStatus
        authorizationStatus = status

        guard !authorizationWaiters.isEmpty else { return }
        // This also fires the moment the delegate is set, well before the user has seen a
        // prompt. A status that's still undetermined isn't an answer, so keep waiting for
        // the one that is, rather than resuming on it and reporting a refusal the user
        // never made.
        guard status != .notDetermined else { return }

        let waiters = authorizationWaiters
        authorizationWaiters = []
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            waiters.forEach { $0.resume() }
        default:
            waiters.forEach { $0.resume(throwing: LocationError.permissionDenied) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !locationWaiters.isEmpty else { return }
        let waiters = locationWaiters
        locationWaiters = []

        if let location = locations.last {
            waiters.forEach { $0.resume(returning: location) }
        } else {
            waiters.forEach { $0.resume(throwing: LocationError.noFix) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !locationWaiters.isEmpty else { return }
        let waiters = locationWaiters
        locationWaiters = []
        waiters.forEach { $0.resume(throwing: error) }
    }
}
