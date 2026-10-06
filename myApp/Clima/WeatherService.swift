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
    /// What the condition is called under the dial — "Sunny", "Light Rain".
    ///
    /// Carried as text rather than worked out from `condition`, because a service that
    /// has its own words for the weather should get to use them: the dial only has eight
    /// slots, but "Drizzle" is a better caption than the "Rainy" its slot is named for.
    let conditionLabel: String
    /// Relative humidity as a whole percent, or nil when the service didn't send one.
    let humidity: Int?
    /// How much fell in the last hour, in inches, or nil when the service didn't say.
    ///
    /// Inches for the same reason `temperature` is Fahrenheit: it's what the rest of the
    /// app stores, and `precipitationText(_:useMetric:)` in Theme is the one place that
    /// converts. The new service reports it directly (`precip1Hour`); for WeatherKit it's
    /// the amount in the last full hour of the hourly forecast.
    let precipitationLastHour: Double?
    /// Today and the six days after it, for the upper strip.
    let daily: [DailyForecast]
    /// Every hour of the forecast from the next one on, one each, for the lower strip —
    /// see `HourlyForecast.stripStart`/`stripLength`.
    ///
    /// A `var`, unlike the rest, so `WeatherSourceSwitch` can fill its gaps from
    /// `HourlyCache` after the service has answered.
    var hourly: [HourlyForecast]
    /// Sunrises and sunsets, at least today's and tomorrow's, in time order. They can
    /// include ones already past or beyond the strip — the screen picks out the ones that
    /// fall between its hours.
    let sunEvents: [SunEvent]

    /// What the place the reading is for is called — "Centreville" — or nil when the
    /// lookup isn't set up or didn't answer. See `LocationNameService`.
    let locationName: String?

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
    /// The new weather service has no address or no API key yet — see `NewWeatherService`.
    case notConfigured
    /// The new weather service answered, but not with a reading: an HTTP error (a 401
    /// usually means a bad API key), or a body missing the fields we need.
    case badResponse(status: Int)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            // The limit isn't named. Interpolating it would read "within 1 seconds" the
            // first time anyone retunes it, and the number doesn't change what the reader
            // does next anyway — it's the same sentence `URLError.timedOut` gets, since
            // it's the same situation. The value is kept on the case for the log, where
            // knowing which limit fired is worth something.
            return "The weather service took too long to answer. Tap the hub to try again."
        case .notConfigured:
            return "The new weather service isn't set up yet."
        case .badResponse:
            // The status code goes to the log, not the screen — see `WeatherErrorMessage`.
            return "Couldn't get the weather right now. Tap the hub to try again."
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

        // Started first so it runs while WeatherKit is answering, rather than after.
        async let locationName = LocationNameService.name(for: location)

        // All three datasets in ONE call. WeatherKit's variadic overload fetches them
        // together, so the dial and both strips are guaranteed to describe the same
        // moment — three separate calls could straddle a condition change and leave the
        // dial disagreeing with the strip directly under it.
        //
        // The hours are asked for by date: WeatherKit's default hourly range is only about
        // a day. The end is `stripLength` hours after the strip's first column, so the
        // strip's last column is the last hour inside the range. The start is the hour
        // just finished — two before the strip's first column. Neither it nor the hour
        // we're in is on the strip, but the finished one is where
        // `precipitationLastHour` reads from.
        let now = Date()
        let calendar = Calendar.current
        let thisHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let stripStart = [HourlyForecast].stripStart(after: now)
        let hoursStart = calendar.date(byAdding: .hour, value: -1, to: thisHour) ?? thisHour
        let hoursEnd = calendar.date(byAdding: .hour, value: [HourlyForecast].stripLength, to: stripStart) ?? stripStart
        let (current, daily, hourly) = try await weatherKit.weather(
            for: location,
            including: .current, .daily,
            .hourly(startDate: hoursStart, endDate: hoursEnd)
        )

        let condition = WeatherCondition(weatherKitCondition: current.condition, isDaylight: current.isDaylight)
        let temperature = Self.fahrenheit(current.temperature)

        return WeatherSnapshot(
            condition: condition,
            temperature: temperature,
            conditionLabel: condition.label,
            // WeatherKit gives 0.0–1.0; the readout shows a whole percent.
            humidity: Int((current.humidity * 100).rounded()),
            precipitationLastHour: Self.precipitationLastHour(from: hourly),
            daily: Self.dailyForecasts(from: daily),
            hourly: Self.hourlyForecasts(from: hourly),
            sunEvents: Self.sunEvents(from: daily),
            locationName: await locationName,
            // Stamped when the answer lands, not when the request left, so the time on
            // screen is the age of the data rather than the age of the attempt.
            fetchedAt: Date()
        )
    }

    // MARK: - WeatherKit's shapes, turned into ours

    /// Today and the six days after it — the seven columns the upper strip draws, in the
    /// order the strip draws them.
    ///
    /// The slots come first and the forecast is matched into them, rather than the
    /// forecast being taken in the order WeatherKit sent it. The two normally agree —
    /// WeatherKit's daily forecast starts at today too — but only matching by date makes
    /// it certain: a list that began a day off, or came back short, would otherwise slide
    /// one day's weather under another day's letter, which is worse than an empty column
    /// — it's a wrong one. Matched, a day with nothing behind it just shows dashes in its
    /// own place.
    ///
    /// Today after its sunset is the one column that shows a night icon — see
    /// `condition(for:isToday:at:)`.
    private static func dailyForecasts(from forecast: Forecast<DayWeather>) -> [DailyForecast] {
        let calendar = Calendar.current
        let now = Date()
        let today = [DailyForecast].stripStart(containing: now)

        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            guard let day = forecast.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) else {
                return DailyForecast(
                    date: date, condition: nil, highTemp: nil, lowTemp: nil, precipitationChance: nil
                )
            }
            // Our own `date`, not `day.date`: the column's position on the strip is what
            // the slot decided, and a WeatherKit day begins in the forecast location's
            // time zone, which needn't agree with the phone's about which day it is.
            return DailyForecast(
                date: date,
                condition: condition(for: day, isToday: offset == 0, at: now),
                highTemp: fahrenheit(day.highTemperature),
                lowTemp: fahrenheit(day.lowTemperature),
                // WeatherKit gives 0.0–1.0; the strip shows a whole percent.
                precipitationChance: Int((day.precipitationChance * 100).rounded())
            )
        }
    }

    /// A day's icon on the strip.
    ///
    /// A day's condition describes its daytime weather, so it normally gets the daytime
    /// icon. Today after sunset is the exception: the day is over as far as anyone
    /// looking at the sky is concerned, so it shows tonight's forecast, moon and all —
    /// the same rule the new service follows. A day with no sunset (the polar summer or
    /// winter) stays on daytime.
    private static func condition(for day: DayWeather, isToday: Bool, at now: Date) -> WeatherCondition {
        if isToday, let sunset = day.sun.sunset, now >= sunset {
            return WeatherCondition(weatherKitCondition: day.overnightForecast.condition, isDaylight: false)
        }
        return WeatherCondition(weatherKitCondition: day.condition, isDaylight: true)
    }

    /// The next `stripLength` hours (72) — see `HourlyForecast.stripStart`.
    ///
    /// Slot-first for the same reason as the days above. The request covers all of these
    /// hours, so normally every one has a reading to show; where the forecast doesn't
    /// reach, that one hour is left for
    /// `HourlyCache` to fill, or renders dashes, and the rest stay exactly where they were.
    private static func hourlyForecasts(from forecast: Forecast<HourWeather>) -> [HourlyForecast] {
        let calendar = Calendar.current

        return [HourlyForecast].placeholder(from: Date()).map { slot in
            guard let hour = forecast.first(
                where: { calendar.isDate($0.date, equalTo: slot.date, toGranularity: .hour) }
            ) else {
                return slot
            }
            return HourlyForecast(
                date: slot.date,
                condition: WeatherCondition(weatherKitCondition: hour.condition, isDaylight: hour.isDaylight),
                temperature: fahrenheit(hour.temperature),
                // WeatherKit gives 0–1; the app stores a whole percent, as for the days.
                precipitationChance: Int((hour.precipitationChance * 100).rounded())
            )
        }
    }

    /// Every sunrise and sunset in the daily forecast, from `DayWeather.sun`. A day near
    /// the poles can be missing one or both, and simply contributes fewer.
    private static func sunEvents(from forecast: Forecast<DayWeather>) -> [SunEvent] {
        forecast.flatMap { day in
            [
                day.sun.sunrise.map { SunEvent(kind: .sunrise, date: $0) },
                day.sun.sunset.map { SunEvent(kind: .sunset, date: $0) },
            ].compactMap { $0 }
        }
        .sorted { $0.date < $1.date }
    }

    /// What fell in the last full hour — 11:00 to 12:00 when it's 12:25 — in inches.
    ///
    /// The nearest thing WeatherKit has to the new service's `precip1Hour`. CurrentWeather
    /// only offers `precipitationIntensity`, a rate at this instant, which reads 0 the
    /// moment a shower stops; the hourly forecast is asked for from an hour before the
    /// strip starts, so the hour just finished is in there with its total. Nil if it's
    /// missing anyway.
    private static func precipitationLastHour(from forecast: Forecast<HourWeather>) -> Double? {
        let calendar = Calendar.current
        guard let thisHour = calendar.dateInterval(of: .hour, for: Date())?.start,
              let lastHour = calendar.date(byAdding: .hour, value: -1, to: thisHour),
              let hour = forecast.first(where: {
                  calendar.isDate($0.date, equalTo: lastHour, toGranularity: .hour)
              })
        else { return nil }
        return hour.precipitationAmount.converted(to: .inches).value
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
    var humidity: Int? = 47
    var precipitationLastHour: Double? = 0.02
    /// The made-up strips from `DailyForecast`/`HourlyForecast`. Only previews read these
    /// now — the running app's strips come from WeatherKit.
    var daily: [DailyForecast] = .sample
    var hourly: [HourlyForecast] = .sample
    var sunEvents: [SunEvent] = .sample
    var locationName: String? = "Centreville"
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
            conditionLabel: condition.label,
            humidity: humidity,
            precipitationLastHour: precipitationLastHour,
            daily: daily,
            hourly: hourly,
            sunEvents: sunEvents,
            locationName: locationName,
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
///
/// Shared by both services rather than private to this file, so the new weather service
/// gives up at the same moment WeatherKit would.
func withTimeout<T: Sendable>(
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
