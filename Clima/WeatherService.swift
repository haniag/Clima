//
//  WeatherService.swift
//  Clima
//

import CoreLocation
import Foundation
import WeatherKit

/// One reading of the weather: everything on the screen, fetched together.
///
/// One value rather than three separate ones because the screen is only ever in one of
/// two states — it has a reading or it doesn't — and a type that can't be half-filled is
/// what makes that true. Three independent properties would allow a fourth state nobody
/// designed: a dial showing rain above a strip that failed to load.
struct WeatherSnapshot {
    let condition: WeatherCondition
    /// Degrees Fahrenheit, already rounded to a whole number.
    ///
    /// Fahrenheit because that's the unit the rest of the app stores and passes around;
    /// `temperatureText(_:useCelsius:)` in Theme is the single place that converts, and
    /// it converts *from* Fahrenheit. Handing views a `Measurement` instead would just
    /// move that decision to every call site.
    let temperature: Int
    /// Monday to Sunday of the current week, for the upper strip.
    let daily: [DailyForecast]
    /// Eight 3-hour blocks covering today, midnight to midnight, for the lower strip.
    let hourly: [HourlyForecast]

    /// When this reading was taken.
    ///
    /// Carried on the reading rather than tracked beside it, because it describes THIS
    /// reading and has to travel with it: the screen holds a snapshot through a failed
    /// refresh, and the whole value of showing a time is that it keeps saying 14:32 while
    /// the clock moves on. A separate "last updated" property on the screen would quietly
    /// advance to the moment of the failed attempt and claim the stale reading was fresh.
    let fetchedAt: Date
}

/// What `WeatherService` itself can fail with, as opposed to what CoreLocation or
/// WeatherKit throw through it.
enum WeatherServiceError: LocalizedError {
    case timedOut(seconds: Int)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            // The limit isn't named. Interpolating it would read "within 1 seconds" the
            // first time anyone retunes it, and the number doesn't change what the reader
            // does next anyway — it's the same sentence `URLError.timedOut` gets, since
            // it's the same situation. The value is kept on the case for the log, where
            // knowing which limit fired is worth something.
            return "The weather service took too long to answer. Tap the hub to try again."
        }
    }
}

/// What the app needs from the weather, stated without mentioning WeatherKit.
///
/// This is the seam CLAUDE.md asks for: views depend on this protocol, never on
/// WeatherKit itself, so previews and tests can hand them `PreviewWeatherService` below
/// and get a dial on screen with no network, no location prompt, and no paid developer
/// account in sight.
protocol WeatherProviding {
    func currentWeather() async throws -> WeatherSnapshot
}

/// The real one: Apple's WeatherKit, asked about wherever `LocationProvider` says we are.
///
/// Every WeatherKit call in the app lives in this one method. That's the whole point of
/// the type — WeatherKit's ~30 conditions, its `Measurement` temperatures and its error
/// vocabulary all stop here, and what comes out the other side is a `WeatherSnapshot`.
final class WeatherService: WeatherProviding {

    private let locationProvider: LocationProvider

    /// Apple's own service object — which is *also* called `WeatherService`, hence the
    /// `WeatherKit.` prefix. A bare `WeatherService` here resolves to the type you're
    /// reading, because a name declared in the app's own module wins over one imported
    /// from a framework; the prefix is what reaches past our own name to theirs.
    ///
    /// `.shared` rather than an instance of our own because WeatherKit expects it: the
    /// shared object is what holds the authentication and the request budget, and making
    /// your own gets you neither.
    private let weatherKit = WeatherKit.WeatherService.shared

    /// The location provider is injected rather than made here so a test or a preview can
    /// substitute one, but it defaults to the real thing so ordinary callers can write
    /// `WeatherService()`.
    ///
    /// `@MainActor` on the initializer only, not on the whole type: building a
    /// `LocationProvider` — and therefore its `CLLocationManager` — has to happen on the
    /// main thread, because that's the queue CoreLocation will deliver every callback on.
    /// `currentWeather()` below stays un-isolated so the waiting it does sits off the main
    /// thread, and the compiler inserts the hop back to main at each `await` on the
    /// provider. That hop is the thing that makes the waiter queues in `LocationProvider`
    /// safe.
    ///
    /// The parameter defaults to `nil` rather than to `LocationProvider()` because a
    /// default-argument expression is evaluated in a non-isolated context whatever the
    /// initializer is marked — so the obvious spelling can't build once the provider is
    /// main-actor bound. Making it optional moves that construction into the body, where
    /// the isolation applies.
    @MainActor
    init(locationProvider: LocationProvider? = nil) {
        self.locationProvider = locationProvider ?? LocationProvider()
    }

    /// How long a fetch gets before it's called off.
    ///
    /// Covers the whole round trip — permission, fix or geocode, and WeatherKit — because
    /// that's the thing the reader is waiting on. Ten seconds is long enough for a slow
    /// cellular connection to answer and short enough that "Updating" doesn't become the
    /// screen's resting state; URLSession's own default of 60 is far past the point where
    /// someone has decided the app is broken.
    static let timeout: Duration = .seconds(10)

    func currentWeather() async throws -> WeatherSnapshot {
        try await withTimeout(Self.timeout) { [self] in
            try await fetchSnapshot()
        }
    }

    private func fetchSnapshot() async throws -> WeatherSnapshot {
        let location = try await locationProvider.currentLocation()

        // All three datasets in ONE call. WeatherKit's variadic overload fetches them
        // together, so the dial and both strips are guaranteed to describe the same
        // moment — three separate calls could straddle a condition change and leave the
        // dial disagreeing with the strip directly under it.
        let (current, daily, hourly) = try await weatherKit.weather(
            for: location,
            including: .current, .daily, .hourly
        )

        return WeatherSnapshot(
            condition: WeatherCondition(weatherKitCondition: current.condition),
            temperature: Self.fahrenheit(current.temperature),
            daily: Self.dailyForecasts(from: daily),
            hourly: Self.hourlyBlocks(from: hourly),
            // Stamped when the answer lands, not when the request left, so the time on
            // screen is the age of the data rather than the age of the attempt.
            fetchedAt: Date()
        )
    }

    // MARK: - WeatherKit's shapes, turned into ours

    /// Monday to Sunday of the current week — the seven columns the upper strip draws,
    /// in the order the strip draws them.
    ///
    /// The slots come first and the forecast is matched into them, rather than the
    /// forecast being taken in the order WeatherKit sent it. WeatherKit answers with
    /// today onwards, so earlier in the week there is simply nothing to put in Monday's
    /// column on a Thursday; building the week first means those columns still exist,
    /// dated and labelled, showing dashes. Taking the list as given would slide Thursday's
    /// weather under Monday's letter, which is worse than an empty column — it's a wrong
    /// one.
    ///
    /// Those earlier columns are then filled from `DailyForecastCache`, which is holding
    /// what Monday's own fetch said back when Monday was today.
    private static func dailyForecasts(from forecast: Forecast<DayWeather>) -> [DailyForecast] {
        let calendar = Calendar.current
        let monday = [DailyForecast].weekStart(containing: Date())

        let week = (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
            guard let day = forecast.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) else {
                return DailyForecast(date: date, condition: nil, highTemp: nil, lowTemp: nil)
            }
            // Our own `date`, not `day.date`: the column's position in the week is what
            // the slot decided, and a WeatherKit day begins in the forecast location's
            // time zone, which needn't agree with the phone's about which day it is.
            return DailyForecast(
                date: date,
                condition: WeatherCondition(weatherKitCondition: day.condition),
                highTemp: fahrenheit(day.highTemperature),
                lowTemp: fahrenheit(day.lowTemperature)
            )
        }

        // Write before reading: this fetch's days go in first, so today's reading is
        // already recorded for when today becomes Tuesday's past. Then the gaps it left
        // come back out.
        DailyForecastCache.save(week)
        return DailyForecastCache.backfill(week)
    }

    /// Today's eight 3-hour blocks: 12AM, 3AM, 6AM, 9AM, 12PM, 3PM, 6PM, 9PM.
    ///
    /// Slot-first for the same reason as the days above. WeatherKit gives every hour of
    /// the current day, including ones already past, so the blocks behind us usually do
    /// have a reading to show; where the forecast doesn't reach back far enough, that one
    /// block renders dashes and the other seven stay exactly where they were.
    private static func hourlyBlocks(from forecast: Forecast<HourWeather>) -> [HourlyForecast] {
        let calendar = Calendar.current
        let start = [HourlyForecast].stripStart(containing: Date())

        return (0..<8).map { index in
            let date = calendar.date(byAdding: .hour, value: index * 3, to: start) ?? start
            guard let hour = forecast.first(
                where: { calendar.isDate($0.date, equalTo: date, toGranularity: .hour) }
            ) else {
                return HourlyForecast(date: date, condition: nil, temperature: nil)
            }
            return HourlyForecast(
                date: date,
                condition: WeatherCondition(weatherKitCondition: hour.condition),
                temperature: fahrenheit(hour.temperature)
            )
        }
    }

    /// The app stores every temperature as a whole number of degrees Fahrenheit; this is
    /// the one place WeatherKit's `Measurement` is unwrapped into that.
    private static func fahrenheit(_ temperature: Measurement<UnitTemperature>) -> Int {
        Int(temperature.converted(to: .fahrenheit).value.rounded())
    }
}

/// A stand-in for previews and tests.
///
/// It can also be told to fail or to stall, which is how the screen's error and loading
/// states get looked at without unplugging the Wi-Fi or waiting for a slow network:
///
/// ```swift
/// PreviewWeatherService(condition: .storm, temperature: 41)
/// PreviewWeatherService(error: LocationProvider.LocationError.permissionDenied)
/// PreviewWeatherService(delay: .seconds(3))
/// ```
struct PreviewWeatherService: WeatherProviding {
    var condition: WeatherCondition = .clear
    var temperature: Int = 72
    /// The made-up strips from `DailyForecast`/`HourlyForecast`. Only previews read these
    /// now — the running app's strips come from WeatherKit.
    var daily: [DailyForecast] = .sample
    var hourly: [HourlyForecast] = .sample
    /// Set this to make every fetch fail instead of answering.
    var error: Error?
    /// How long to stall before answering, for a look at the loading state. Not subject to
    /// `WeatherService.timeout` — that belongs to the real service, so a preview can still
    /// stall indefinitely to be looked at.
    var delay: Duration = .zero
    /// What the "updated" line should read. Fixed rather than `Date()` so preview
    /// snapshots don't change every time the canvas redraws.
    var fetchedAt: Date = .now

    func currentWeather() async throws -> WeatherSnapshot {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        if let error {
            throw error
        }
        return WeatherSnapshot(
            condition: condition,
            temperature: temperature,
            daily: daily,
            hourly: hourly,
            fetchedAt: fetchedAt
        )
    }
}

/// Runs `operation`, giving up if it hasn't answered within `duration`.
///
/// Two children race: the real work, and a sleep that throws when it wakes. Whichever
/// finishes first is the result, and the loser is cancelled on the way out.
///
/// One honest limit: a task group waits for its children before returning, so this
/// returns promptly only if the work actually responds to cancellation. WeatherKit's
/// requests (URLSession) and `CLGeocoder` both do. A `CLLocationManager` fix does not —
/// it answers when CoreLocation calls back — but CoreLocation applies its own timeout to
/// that and always calls back eventually, so this can't wedge permanently.
private func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw WeatherServiceError.timedOut(seconds: Int(duration.components.seconds))
        }

        // `next()` can't be nil here: two tasks were just added, so there's always a
        // first one to finish.
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
