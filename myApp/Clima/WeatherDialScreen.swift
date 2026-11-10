//
//  WeatherDialScreen.swift
//  Clima
//

import SwiftUI

/// The app's one screen: the dial, the current reading, the two forecast strips, and
/// the settings.
///
/// Laid out on a single grid — one page margin, one gap between blocks, one rule under
/// every caption — so the eye can move down the page in steps of the same size. There
/// are no cards and no shadows: blocks are separated by space and by a hairline, which
/// is the least amount of design that still does the job.
struct WeatherDialScreen: View {
    /// Where the reading comes from. A protocol, not `WeatherService` itself, so a
    /// preview can hand this screen a `PreviewWeatherService` and get a dial on screen
    /// with no network, no location prompt and no developer account — see the three
    /// previews at the bottom of this file.
    let weatherService: WeatherProviding

    /// The last good reading, or nil until the first one lands.
    ///
    /// Deliberately kept through both a refresh and a failure. The alternative — clearing
    /// it whenever a fetch starts — would blank the dial and the temperature every time
    /// the hub is tapped, and would turn a dropped network into an empty screen. A
    /// slightly stale reading with a note explaining why is more use than no reading.
    @State private var snapshot: WeatherSnapshot?

    /// What the readout should say about the fetch itself, as opposed to about the
    /// weather. Separate from `snapshot` because the two are genuinely independent: a
    /// failed refresh still has a perfectly good previous reading behind it.
    @State private var status: FetchStatus = .loading

    enum FetchStatus: Equatable {
        case loading
        case ready
        /// The sentence to show, and whether the cause is the app not being allowed the
        /// phone's location — the one failure that gets buttons under it; see
        /// `locationDeniedActions`.
        case failed(String, locationDenied: Bool)
    }

    // Shared across every view that reads them (same UserDefaults key), so changing
    // either one here updates the readings immediately. Appearance is applied by this
    // screen's own `.preferredColorScheme` below, rather than up on `ClimaApp`'s
    // WindowGroup, so the Light/Dark switch works in the canvas too.
    @AppStorage("useCelsius") private var useCelsius = TemperatureUnit.phoneUsesCelsius

    /// The Light/Dark switch's setting, or `nil` if it's never been touched — in which
    /// case the app follows the phone's own appearance. A new key rather than the old
    /// `isDarkMode`, which always had a value, so nobody starts out pinned to Light.
    @AppStorage("darkModeOverride") private var darkModeOverride: Bool?

    /// Which weather service answers. Chosen on the app's page in the iPhone's Settings
    /// app and read by `WeatherSourceSwitch` on every fetch; the screen watches it to
    /// fetch again when it changes, and hands it to the location search, which searches
    /// the same service.
    @AppStorage(WeatherSource.key) private var weatherSource: WeatherSource = .default

    /// The column at the hourly strip's leading edge. Set to the strip's first column
    /// whenever a reading lands; the reader's swiping moves it in between.
    @State private var hourlyScrollPosition: HourlyStripItem.ID?

    /// Which of the hourly strip's columns is under its pinned marker right now, updated
    /// continuously while it's swiped — unlike `hourlyScrollPosition`, which only settles
    /// once the strip stops. Drives the 7-day strip's marker; see `markedDay`.
    @State private var hourlyMarkedIndex = 0

    /// The hourly strip's columns: the reading's hours from the next one on, with the
    /// sunrises and sunsets among them. Built by `stripItems(from:at:)` when a reading
    /// lands and once a minute after that, and kept here in between — the strip reads the
    /// list on every frame of a swipe, and building it means filtering and sorting about
    /// 170 hours.
    @State private var stripItems = WeatherDialScreen.stripItems(from: nil, at: Date())

    /// Whether the next reading to land should bring the hourly strip back to its start.
    /// Set by `show(_:resetStrip:)`, read by the strip when the reading arrives.
    @State private var returnStripToStart = true

    /// When the last fetch was started, whoever started it — see `minuteTick()`.
    @State private var lastAttemptAt = Date.distantPast

    /// Whether the location search sheet is open — see the header's arrow.
    @State private var isSearchingLocation = false

    /// Opens the app's page in the Settings app — see `locationDeniedActions`.
    @Environment(\.openURL) private var openURL

    /// The appearance actually on screen. With no override this is the phone's, since
    /// `.preferredColorScheme(nil)` below leaves the system's choice in place.
    @Environment(\.colorScheme) private var colorScheme

    /// What the switch shows and sets: the phone's appearance until it's flipped, and
    /// from then on whatever it was flipped to.
    private var isDarkMode: Binding<Bool> {
        Binding(
            get: { darkModeOverride ?? (colorScheme == .dark) },
            set: { darkModeOverride = $0 }
        )
    }

    /// Set once, at the root, from the real screen width — see `Theme.tunedScreenWidth`
    /// and `EnvironmentValues.deviceScale`. Every fixed size below multiplies by this.
    @Environment(\.deviceScale) private var deviceScale

    /// Whether the app is on screen, so coming back to it can refresh a stale reading.
    @Environment(\.scenePhase) private var scenePhase

    /// How old a reading has to be before returning to the app replaces it.
    ///
    /// A gate rather than an unconditional refresh, because WeatherKit bills by the call
    /// and the free tier is 500,000 a month for the whole developer account. Refreshing
    /// on every glance would turn a handful of fetches per user per day into dozens, and
    /// divide how many people the app can serve by the same factor. Ten minutes is about
    /// as fast as the weather itself moves, and the "Updated" line means a reading that's
    /// slightly behind is visibly behind rather than silently so.
    private static let staleAfter: TimeInterval = 10 * 60

    /// How long the app waits after any fetch before starting another one by itself.
    ///
    /// Only matters while fetches are failing: a good reading isn't stale for ten
    /// minutes, but a failed one leaves the old reading stale straight away, and without
    /// this the once-a-minute check would try again every minute for as long as the
    /// phone was offline.
    private static let retryAfter: TimeInterval = 2 * 60

    var body: some View {
        // The drawer is a bottom bar, not the last block on the page: it stays put while
        // the page scrolls behind it, so it can't live inside the scroll content. It sits
        // alongside it instead, floating a margin clear of the screen's bottom edge, and
        // the scroll content reserves room for it.
        ZStack(alignment: .bottom) {
            page
            SettingsDrawer(useCelsius: $useCelsius, isDarkMode: isDarkMode)
                .padding(.bottom, SettingsDrawer.bottomMargin(scale: deviceScale))
        }
        // On the stack, not on the drawer: a fixed-size child can't grow into the safe
        // area on its own, it can only be *positioned* in whatever box its parent gives
        // it. Widening the box is what lets the bar's own margin be measured from the
        // screen's physical edge rather than from the top of the home indicator's strip,
        // which would push it another 34pt up the page.
        .ignoresSafeArea(edges: .bottom)
        .background(Theme.canvas.ignoresSafeArea())
        // Follows the phone's Light/Dark setting until the drawer's switch is flipped;
        // after that the switch wins, so a phone in dark mode doesn't override a
        // drawer that reads "Light". `nil` is what hands the choice back to the system.
        //
        // It lives here rather than on `ClimaApp`'s WindowGroup because a SwiftUI
        // preview renders this screen directly and never runs the App: with the
        // modifier up there, flipping the switch in the canvas changed the setting
        // but nothing on screen, since nothing in the preview was reading it.
        .preferredColorScheme(darkModeOverride.map { $0 ? .dark : .light })
        // `.task` rather than `.onAppear` so the fetch is tied to this view's lifetime:
        // if the screen goes away mid-request, the request is cancelled with it.
        // Before the first fetch rather than instead of it: the reading kept from the
        // last launch goes on screen straight away, and the fetch below replaces it.
        .onAppear(perform: showSavedReading)
        .task { await load() }
        // Left open on a desk, the app would otherwise show the same reading all
        // afternoon: nothing above fetches unless the app is opened, returned to, or
        // tapped. So while it's on screen it checks once a minute — see `minuteTick()`.
        // Tied to `scenePhase`, so the checking stops when the app leaves the screen and
        // starts again when it comes back.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                minuteTick()
            }
        }
        // Left in a pocket for an hour, the app would otherwise still be showing the
        // reading it had when it went in there. `.onChange` doesn't fire for the initial
        // value, so this can't double up with the `.task` above on launch — and even if
        // the scene passes through `.inactive` on the way up, `refresh()` declines while
        // that first fetch is still running.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Time has passed while the app was away, whether or not enough for a new
            // reading: the strip should open on the hour that's next now.
            rebuildStripItems()
            guard isReadingStale else { return }
            refresh()
        }
        // Switched in the Settings app: fetch from the newly chosen service straight away,
        // however fresh the current reading is, so what's on screen is its, not the
        // other's. `load()` rather than `refresh()`, because `refresh()` declines while a
        // fetch is running — and one from the old service is exactly what should be
        // overtaken. `fetchGeneration` stops its answer replacing the new one if it lands
        // late.
        .onChange(of: weatherSource) {
            Task { await load() }
        }
        // The lock screen widget reads its unit from what was last saved, so a flip of
        // the °F/°C switch is saved straight away rather than waiting for the next fetch.
        .onChange(of: useCelsius) {
            guard let snapshot else { return }
            WidgetWeather.publish(snapshot, useCelsius: useCelsius)
        }
        .sheet(isPresented: $isSearchingLocation) {
            LocationSearchSheet(current: ChosenPlace.saved, source: weatherSource) { place in
                ChosenPlace.choose(place)
                // `load()` for the same reason as a change of source: the new place's
                // weather should replace whatever is on screen or on its way.
                Task { await load() }
            }
            // The sheet is a window of its own, so the Light/Dark switch has to reach it
            // separately.
            .preferredColorScheme(darkModeOverride.map { $0 ? .dark : .light })
        }
    }

    /// Whether what's on screen is old enough to be worth replacing.
    ///
    /// No reading at all counts as stale: if the first attempt failed while you were away,
    /// coming back is a good moment to try again.
    private var isReadingStale: Bool {
        guard let snapshot else { return true }
        return Date().timeIntervalSince(snapshot.fetchedAt) > Self.staleAfter
    }

    /// Starts a fetch on someone's behalf — the hub, or a return to the app — unless one
    /// is already running.
    ///
    /// The guard is about cost, not correctness: overlapping fetches are already handled
    /// safely by `fetchGeneration` below, but each one still spends a WeatherKit call, and
    /// the hub can be tapped as fast as a finger moves. Declining costs nothing in
    /// feedback either, since the dial spins from the tap itself rather than from the
    /// fetch.
    ///
    /// `.task` calls `load()` directly rather than coming through here, because `status`
    /// starts out `.loading` — the very first fetch would decline itself.
    ///
    /// `resetStrip` is whether the hourly strip should swipe itself back to its start when
    /// the reading lands. Yes when someone asked for the reading; no when the app fetched
    /// by itself, which shouldn't pull the strip out from under a finger.
    private func refresh(resetStrip: Bool = true) {
        guard status != .loading else { return }
        Task { await load(resetStrip: resetStrip) }
    }

    /// Runs once a minute while the app is on screen.
    ///
    /// Every minute it rebuilds the hourly strip, so an hour that has gone by drops off
    /// the front. And once the reading is older than `staleAfter`, it fetches a new one —
    /// the same ten-minute gate a return to the app goes through, so an app left open
    /// costs no more fetches than one opened every ten minutes.
    private func minuteTick() {
        rebuildStripItems()
        guard isReadingStale,
              Date().timeIntervalSince(lastAttemptAt) > Self.retryAfter
        else { return }
        refresh(resetStrip: false)
    }

    /// Puts the reading kept from the last launch on screen, if there is one and nothing
    /// newer has arrived first. `status` is left at `.loading`, so the readout says
    /// "Updating" under it until the first fetch answers.
    private func showSavedReading() {
        guard snapshot == nil, let saved = weatherService.savedWeather else { return }
        show(saved, resetStrip: true)
    }

    /// Puts a reading on screen, and rebuilds the hourly strip's columns from it.
    ///
    /// The strip goes back to its start if it was asked to, or if that's where it already
    /// was — its first hour may have changed, and it should stay on what's next.
    private func show(_ reading: WeatherSnapshot, resetStrip: Bool) {
        returnStripToStart = resetStrip || isStripAtStart
        snapshot = reading
        stripItems = Self.stripItems(from: reading, at: Date())
    }

    /// Rebuilds the hourly strip's columns for the time it is now, from the reading
    /// already on screen. A strip resting at its start stays at its start.
    private func rebuildStripItems() {
        let wasAtStart = isStripAtStart
        stripItems = Self.stripItems(from: snapshot, at: Date())
        if wasAtStart {
            scrollHourlyToStart()
        }
    }

    /// Whether the hourly strip is on its first column — or hasn't been placed yet.
    private var isStripAtStart: Bool {
        hourlyScrollPosition == nil || hourlyScrollPosition == stripItems.first?.id
    }

    /// Counts fetches so a slow one can tell it has been overtaken.
    ///
    /// The hub can be tapped while a fetch is still running, which leaves two in flight at
    /// once and no guarantee they finish in the order they started. Without this, a slow
    /// failing fetch could land *after* a fast successful one and replace a good reading
    /// with an error message — the screen showing a failure that a later attempt had
    /// already recovered from.
    @State private var fetchGeneration = 0

    /// Asks for a fresh reading, and records what came back.
    ///
    /// Never throws: every outcome is a thing the readout knows how to display, so the
    /// error is turned into a sentence here rather than propagated to a caller that
    /// would only have to do the same.
    private func load(resetStrip: Bool = true) async {
        fetchGeneration += 1
        let generation = fetchGeneration
        lastAttemptAt = Date()
        status = .loading

        do {
            let reading = try await weatherService.currentWeather()
            // Somebody started a newer fetch while this one was out. Their answer is the
            // one that should win, so this one retires quietly.
            guard generation == fetchGeneration else { return }
            show(reading, resetStrip: resetStrip)
            status = .ready
            WidgetWeather.publish(reading, useCelsius: useCelsius)
        } catch {
            guard generation == fetchGeneration else { return }
            // A cancelled fetch isn't a failed one — the screen is going away, or a newer
            // request replaced this one. Reporting it would put an error under a dial
            // nobody is looking at, and leave it there.
            if error is CancellationError || Task.isCancelled { return }
            // Never `error.localizedDescription` straight to the screen — see
            // `WeatherErrorMessage`, which picks the sentence a reader can act on and
            // sends the raw error to the console instead.
            status = .failed(
                WeatherErrorMessage.text(for: error),
                locationDenied: WeatherErrorMessage.isLocationDenied(error)
            )
        }
    }

    private var page: some View {
        ScrollView {
            VStack(spacing: Theme.blockGap * deviceScale) {
                header

                // Passed through as an optional: with no reading the dial highlights
                // nothing, rather than sitting lit on `.clear` and telling the reader it's
                // sunny out while the readout underneath says there's no reading.
                DialView(condition: snapshot?.condition, onRefresh: { refresh() })
                    // The hub hangs below the dial's own layout frame; reserve that
                    // space so the reading below it isn't pushed into the hub.
                    .padding(.bottom, DialView.hubOverhang(scale: deviceScale))
                    // Negative padding lets the canopy bleed past the page's usual
                    // gutter and sit closer to the screen edge, without widening the
                    // gutter everything else on the page still respects. See
                    // `dialBleed` — it's worked out from the same scale as everything
                    // else, so the canopy keeps the same ~11pt final margin regardless
                    // of which iPhone this renders on.
                    .padding(.horizontal, -dialBleed)

                readout

                VStack(spacing: Theme.stripGap * deviceScale) {
                    hourlyStrip

                    strip {
                        // Worked out once here rather than once per column.
                        let marked = markedDay
                        ForEach(snapshot?.daily ?? .placeholder(in: timeZone)) { day in
                            ForecastDayColumn(
                                day: day,
                                isMarked: calendar.isDate(day.date, inSameDayAs: marked),
                                onSelect: { showHours(for: day.date) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter * deviceScale)
            // Room for the bar the page now scrolls behind: the bar itself, the margin
            // holding it off the screen's edge, and a gap above it. The stack ignores the
            // bottom safe area, so the scroll view is no longer keeping any of that strip
            // clear on its own.
            //
            // `stripGap` rather than `blockGap`: the bar has the panels' width, corners
            // and moulded edge, so it reads as the third panel in their stack, and needs
            // no more room above it than the 7-day one leaves under the hourly. (It's
            // pinned to the bottom, so any spare height on a taller phone lands here.)
            .padding(.bottom, SettingsDrawer.height(scale: deviceScale)
                + SettingsDrawer.bottomMargin(scale: deviceScale)
                + Theme.stripGap * deviceScale)
        }
        // Only scroll when the content genuinely doesn't fit: on a large phone the page
        // should sit still, not bounce.
        .scrollBounceBehavior(.basedOnSize)
        // SwiftUI's own setting, read by the forecast columns for their labels — see
        // `timeZone` below.
        .environment(\.timeZone, timeZone)
    }

    /// The time zone the strips count and label their days and hours in: the reading's
    /// place's, or the phone's before there's a reading.
    private var timeZone: TimeZone {
        snapshot?.timeZone ?? .current
    }

    /// The calendar in that time zone.
    private var calendar: Calendar {
        Calendar.local(to: timeZone)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            // Where the reading is for. `climaCaps` uppercases it, so this reads
            // "CENTREVILLE" on screen. Blank until a name is known — a space rather than
            // nothing, so the header keeps its height and nothing below it jumps when the
            // name arrives. One line, cut short with an ellipsis, so a long place name
            // can't push the "Updated" time onto a second line.
            //
            // With the arrow after it, the name is also the way to another place's
            // weather: the two together are one button, so a tap on either opens the
            // search.
            Button {
                isSearchingLocation = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8 * deviceScale) {
                    locationName
                    Image(systemName: "chevron.down")
                        .font(.system(size: Theme.captionSize * deviceScale, weight: .semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
                // A finger-sized target without a taller header: the padding widens
                // what can be tapped, and the negative padding after it takes the
                // same room back out of the layout.
                .padding(.vertical, 12 * deviceScale)
                .padding(.trailing, 16 * deviceScale)
                .contentShape(Rectangle())
                .padding(.vertical, -12 * deviceScale)
                .padding(.trailing, -16 * deviceScale)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose another location")

            Spacer()

            // Shown whenever there IS a reading, not only when one has gone stale. A
            // time that appears only on failure is itself a warning sign, and the reader
            // has to learn what its absence means; a time that's always there is just a
            // fact about the reading, and quietly answers "is this current?" without
            // anyone having to ask.
            //
            // It has the header's right-hand end to itself — there's no date — and it's
            // the same size as the place name beside it, so the header keeps the same
            // height whether or not there's a reading yet.
            if let updatedLabel {
                Text(updatedLabel)
                    .climaCaps(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
    }

    /// The header's place name — see `header`.
    private var locationName: some View {
        Text(snapshot?.locationName ?? " ")
            .climaCaps(.caption, bold: true)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
    }

    /// How far past the page's normal `Theme.gutter` margin the canopy is allowed to
    /// bleed. Both the canopy's own diameter and the page's normal content width scale
    /// by the same `deviceScale`, so this comes out proportionally the same — ~11pt of
    /// final margin — on every iPhone, not just the one this was originally tuned on.
    private var dialBleed: CGFloat {
        let normalContentWidth = Theme.tunedScreenWidth - 2 * Theme.gutter
        return (DialView.diameter(scale: 1) - normalContentWidth) / 2 * deviceScale
    }

    /// The same idea for the forecast panels, but measured against the canopy's painted
    /// width rather than its layout frame — see `DialView.canopyWidth(scale:)`. Matching
    /// the frame instead put the panels about 6pt past the curve on each side, which
    /// reads as the panels being wider than the dial rather than level with it.
    private var stripBleed: CGFloat {
        let normalContentWidth = Theme.tunedScreenWidth - 2 * Theme.gutter
        return (DialView.canopyWidth(scale: 1) - normalContentWidth) / 2 * deviceScale
    }

    // MARK: - The current reading

    /// The number is the largest thing on the page and the condition names it
    /// underneath — the dial has already shown *which* condition, so the text only has
    /// to confirm it.
    ///
    /// It doubles as the app's status panel. There's no separate spinner and no error
    /// screen: the page keeps its shape in every state, and this one block says which
    /// state that is — the way an instrument's own display reports a fault rather than
    /// being replaced by a warning light.
    private var readout: some View {
        VStack(spacing: 14 * deviceScale) {
            reading

            // Outside `reading`, which VoiceOver reads as one element: these have to stay
            // two buttons it can land on separately.
            if case .failed(_, locationDenied: true) = status {
                locationDeniedActions
            }
        }
    }

    private var reading: some View {
        VStack(spacing: 4 * deviceScale) {
            // The smaller readings sit to the right of the temperature, the bottom one on
            // its baseline. An invisible copy on the left balances them, so the number
            // itself stays centred under the dial's pointer — without it, sharing a row
            // would push the temperature left by half their width.
            HStack(alignment: .lastTextBaseline, spacing: 8 * deviceScale) {
                sideReadings
                    .hidden()
                    .accessibilityHidden(true)

                Text(readoutValue)
                    .font(Theme.readoutFont(scale: deviceScale))
                    .foregroundStyle(Theme.readoutInk)
                    .contentTransition(.numericText())

                sideReadings
            }

            // `inkMuted`, like "Updated" in the header. It once shared the big number's
            // colour, which was a much paler grey then, and at this size that read as a
            // light weight.
            Text(readoutCaption)
                .climaCaps(.caption)
                .foregroundStyle(Theme.inkMuted)

            if case .failed(let message, _) = status {
                // Sentence case, not the tracked-out caps above: these run to a line or
                // two and name a place to go in Settings, so they have to be read rather
                // than merely registered.
                Text(message)
                    .font(Theme.valueFont(scale: deviceScale))
                    .foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.top, 6 * deviceScale)
                    .padding(.horizontal, Theme.gutter * deviceScale)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The two ways out of "Clima needs your location": switch it back on, or stop
    /// needing it by choosing a place by name.
    ///
    /// Shown only for that failure. Every other one is fixed by trying again, and the hub
    /// is already the button for that.
    private var locationDeniedActions: some View {
        HStack(spacing: 10 * deviceScale) {
            readoutButton("Open Settings") {
                // The app's own page in Settings, which is where its Location row is.
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            readoutButton("Choose a place") {
                isSearchingLocation = true
            }
        }
    }

    /// A small outlined button in the app's label style — quiet enough to sit under the
    /// readout without competing with it.
    private func readoutButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .climaCaps(.small, bold: true)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14 * deviceScale)
                .padding(.vertical, 10 * deviceScale)
                .overlay(Capsule().strokeBorder(Theme.inkMuted, lineWidth: deviceScale))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// A dash until there's a real reading — the same placeholder a physical gauge shows
    /// when its sensor hasn't reported yet, rather than a plausible-looking zero the eye
    /// would take for a measurement.
    ///
    /// No degree sign next to the dash: a unit with nothing to qualify reads as a stray
    /// mark, and at this size the gap between the two was wide enough to look like a
    /// layout fault rather than a deliberate blank.
    private var readoutValue: String {
        guard let snapshot else { return "—" }
        return temperatureText(snapshot.temperature, useCelsius: useCelsius)
    }

    /// "Updated 14:32" — "Updated 2:32 PM" on a phone set to 12-hour time — or nil when
    /// there's no reading to date.
    ///
    /// The day is added once the reading is no longer from today — which happens if the
    /// app is left open overnight — because a bare "04:15" on a reading twelve hours old
    /// looks exactly like one from four minutes ago.
    ///
    /// On the phone's clock, unlike the strips: it says how fresh the reading is, which
    /// is a question about the reader's own time, wherever the weather is for.
    private var updatedLabel: String? {
        guard let snapshot else { return nil }

        // `formatted` writes both the way the phone's region and clock settings say to.
        let time = snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)
        guard !Calendar.current.isDateInToday(snapshot.fetchedAt) else {
            return "Updated \(time)"
        }
        let day = snapshot.fetchedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "Updated \(day) \(time)"
    }

    private var readoutCaption: String {
        switch status {
        case .loading:
            return "Updating"
        case .ready, .failed:
            // A failed refresh still names the condition it managed to read last time;
            // the sentence underneath is what explains that it's no longer fresh. Only a
            // failure with nothing behind it has no condition to name.
            return snapshot?.conditionLabel ?? "No reading"
        }
    }

    /// Precipitation in the last hour, above humidity, above wind — whichever of the three
    /// the reading has. Empty with no reading, so the dash under the dial stays centred.
    ///
    /// Leading-aligned so the icons line up in a column and the numbers start at the
    /// same place.
    @ViewBuilder
    private var sideReadings: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 4 * deviceScale) {
                if let precipitation = snapshot.precipitationLastHour {
                    sideReading(
                        icon: Image("precipitation"),
                        value: precipitationText(precipitation, useMetric: useCelsius)
                    )
                    .accessibilityLabel(
                        "Precipitation in the last hour, "
                            + precipitationText(precipitation, useMetric: useCelsius)
                                .replacingOccurrences(of: " in", with: " inches")
                                .replacingOccurrences(of: " mm", with: " millimetres")
                    )
                }
                if let humidity = snapshot.humidity {
                    // The half-filled drop, deliberately not the precipitation one above
                    // it, so the two readings can't be mistaken for each other.
                    sideReading(icon: Image("humidity"), value: "\(humidity)%")
                        .accessibilityLabel("Humidity \(humidity) percent")
                }
                if let wind = snapshot.windSpeed {
                    // Apple's own wind symbol rather than artwork of ours: the dial's
                    // "windy" icon is drawn for 70pt and turns to a smudge at 16.
                    sideReading(
                        icon: Image(systemName: "wind"),
                        value: windText(wind, useMetric: useCelsius)
                    )
                    .accessibilityLabel(
                        "Wind "
                            + windText(wind, useMetric: useCelsius)
                                .replacingOccurrences(of: " mph", with: " miles per hour")
                                .replacingOccurrences(of: " km/h", with: " kilometres per hour")
                    )
                }
            }
        }
    }

    private func sideReading(icon: Image, value: String) -> some View {
        HStack(spacing: 2 * deviceScale) {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 16 * deviceScale, height: 16 * deviceScale)
            Text(value)
                .font(Theme.valueFont(scale: deviceScale))
        }
        .foregroundStyle(Theme.inkMuted)
    }

    // MARK: - Forecast strips

    /// A row of columns on its own panel. The "now" marker sits flush with the panel's
    /// top edge, so the red mark reads as part of the panel rather than floating inside
    /// it — and it's the only thing distinguishing that column, now that the columns no
    /// longer differ in colour. The 7-day strip marks the day the hourly strip above has
    /// been swiped to; the hourly strip pins its own marker over its first slot.
    private func strip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        stripPanel {
            HStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, stripInset)
        }
    }

    /// Every forecast hour from the next one on, as a row that swipes sideways, with a
    /// column for each sunrise and sunset between the hours it falls between.
    ///
    /// Eight columns fit across the panel, the same width the columns had as eight
    /// 3-hour blocks, and a sliver of the ninth shows at the edge to say there's more.
    /// Swiping settles on whole columns, and the strip opens at its start — see
    /// `scrollHourlyToStart()`.
    ///
    /// The "now" marker doesn't travel with a column: it's pinned over the first slot,
    /// so it's always on screen and the hours slide underneath it. At rest it points at
    /// the next hour; swiped, it points at whichever hour has reached it, and the 7-day
    /// strip's marker follows that hour's day — see `markedDay`.
    private var hourlyStrip: some View {
        stripPanel {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(stripItems) { item in
                        Group {
                            switch item {
                            case .hour(let hour):
                                HourlyColumn(hour: hour)
                            case .sun(let event):
                                SunEventColumn(event: event)
                            }
                        }
                        .containerRelativeFrame(.horizontal, count: 8, spacing: 0)
                    }
                }
                .scrollTargetLayout()
            }
            // The pinned marker. Laid out as the first of eight equal slots across the
            // same inset the columns rest at, so it sits exactly over a column at rest,
            // and at the top, in the slot every column keeps clear for it. On the scroll
            // view rather than in it, so swiping doesn't move it; and it lets touches
            // through, so a swipe that starts on it still moves the hours.
            .overlay(alignment: .top) {
                HStack(spacing: 0) {
                    StripMarker()
                        .frame(maxWidth: .infinity)
                    ForEach(1..<8, id: \.self) { _ in
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: 0)
                    }
                }
                .padding(.horizontal, stripInset)
                .allowsHitTesting(false)
            }
            // Margins rather than padding, so a column swiped past them still shows right
            // out to the panel's edge, while a column at rest sits `stripInset` in, clear
            // of the corners the same as the 7-day strip's.
            .contentMargins(.horizontal, stripInset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $hourlyScrollPosition, anchor: .leading)
            // Which column is under the pinned marker, read continuously while the strip
            // moves, so the 7-day marker follows mid-swipe — see `markedDay`. It's the
            // column nearest the marker: tomorrow's 00 counts once it's swiped more
            // than halfway under it, and stops counting once it's swiped back out.
            //
            // Every column is the same width, so the content's width shared out between
            // them gives that width. The content's own coordinates start at the first
            // column's leading edge, and `contentOffset` is where the panel's left edge
            // sits in them; the marker's slot starts the leading margin on from there,
            // so that's how far the strip has travelled under it.
            .onScrollGeometryChange(for: Int.self) { geometry in
                let count = stripItems.count
                guard count > 0, geometry.contentSize.width > 0 else { return 0 }
                let columnWidth = geometry.contentSize.width / CGFloat(count)
                let travelled = geometry.contentOffset.x + geometry.contentInsets.leading
                let index = Int((travelled / columnWidth).rounded())
                return min(max(index, 0), count - 1)
            } action: { _, index in
                hourlyMarkedIndex = index
            }
        }
        .onAppear(perform: scrollHourlyToStart)
        .onChange(of: snapshot?.fetchedAt) {
            if returnStripToStart {
                scrollHourlyToStart()
            }
        }
    }

    /// Brings the strip back to its first column when the screen appears and when a new
    /// reading that was asked for lands, so a refresh also puts what's next back where
    /// it's expected.
    private func scrollHourlyToStart() {
        hourlyScrollPosition = stripItems.first?.id
    }

    /// Swipes the hourly strip to `day`, for a tap on its column in the 7-day strip: the
    /// day's sunrise lands under the pinned marker, and the 7-day marker follows on its
    /// own, the same as if the hours had been swiped there by hand.
    ///
    /// Today's sunrise is often already gone, and a day near the poles may have none; then
    /// it's the day's first column instead — for today, the strip's start. A day the hours
    /// don't reach leaves the strip where it is.
    private func showHours(for day: Date) {
        let items = stripItems
        let dayItems = items.filter { calendar.isDate($0.id.date, inSameDayAs: day) }
        let sunrise = dayItems.first { item in
            if case .sun(let event) = item, event.kind == .sunrise { return true }
            return false
        }
        // Late enough tonight, the strip already starts on tomorrow, so today has no
        // columns left; tapping it still brings the strip home.
        let fallback = calendar.isDateInToday(day) ? items.first : nil
        guard let target = sunrise ?? dayItems.first ?? fallback else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            hourlyScrollPosition = target.id
        }
    }

    /// The day the 7-day strip marks: the day of the column under the hourly strip's
    /// pinned marker. Swiping tomorrow's 00 under the marker moves the 7-day marker
    /// below onto tomorrow, and swiping it back out brings the marker home.
    private var markedDay: Date {
        let items = stripItems
        guard items.indices.contains(hourlyMarkedIndex) else { return Date() }
        return items[hourlyMarkedIndex].id.date
    }

    /// The reading's hours from the next one on, with the sunrises and sunsets that fall
    /// among them slotted in by time.
    ///
    /// The services already start the strip at the next hour, but the screen keeps a
    /// reading through a failed refresh, and by then that hour may have come and gone.
    /// Trimming here means the strip still opens on what's next rather than on an hour
    /// gone by. Sunrises and sunsets are trimmed to the same window: anything still to
    /// come — so one due before the first hour column leads the strip — up to the last
    /// hour column.
    ///
    /// A function of the reading and the time and nothing else, so it can be worked out
    /// once and kept — see `stripItems` — rather than on every frame of a swipe.
    private static func stripItems(from snapshot: WeatherSnapshot?, at now: Date) -> [HourlyStripItem] {
        let timeZone = snapshot?.timeZone ?? .current
        let firstHour = [HourlyForecast].stripStart(after: now, in: timeZone)
        var hours = (snapshot?.hourly ?? .placeholder(in: timeZone)).filter { $0.date >= firstHour }
        // A reading so old that none of its hours are left: show empty slots instead.
        if hours.isEmpty {
            hours = .placeholder(in: timeZone)
        }
        let lastHour = hours.last?.date ?? firstHour
        let sunEvents = (snapshot?.sunEvents ?? []).filter { $0.date > now && $0.date < lastHour }

        return (hours.map(HourlyStripItem.hour) + sunEvents.map(HourlyStripItem.sun))
            .sorted { $0.sortKey < $1.sortKey }
    }

    /// How far in from the panel's sides the columns sit: far enough that the "now"
    /// marker on the FIRST or LAST column still clears the panel's rounded corners. The
    /// marker's bar is flush with the top edge, which is exactly where the corner curve
    /// bites deepest — measured, it reaches about 18pt in from the panel's side on that
    /// first row. At the old 6pt inset the bar started 11pt in on the daily strip and
    /// only 8pt in on the hourly one (same panel width, 8 columns instead of 7), so the
    /// curve cut a notch off its end in both.
    ///
    /// 19 is the least that clears the tighter of the two, and it is close to the most
    /// this panel can give: the hourly columns come out about 41.5pt, against the 41pt
    /// `baseStripContentWidth` their icons are framed at, so there is only about half a
    /// point left in hand. If a future change needs more room here, the number to
    /// reconsider is the marker bar's own width rather than this inset.
    private var stripInset: CGFloat { 19 * deviceScale }

    /// The panel both strips sit on: its surface, moulded edge and rounded corners, and
    /// its bleed out to the canopy's width. The content brings its own side inset.
    private func stripPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let panelShape = RoundedRectangle(cornerRadius: baseStripCornerRadius * deviceScale, style: .continuous)
        return content()
        // Trimmed from 14, along with the column's top padding, when the hourly strip
        // gained its rain-chance row — the two together are what keep the page from
        // scrolling on a 16 Pro-proportioned screen.
        .padding(.bottom, 10 * deviceScale)
        // The panel surface and its edge shading together, BEHIND the columns rather
        // than the shading lying over them. The "now" marker is flush with the panel's
        // top edge, right where that shading is heaviest, so over the top it came out
        // markedly darker than `Theme.indexMark` and no longer matched the dial
        // pointer it echoes. Nothing else in the panel reaches near enough to an edge
        // for the move to touch it — the day letters clear the top shading by roughly
        // twice its reach — so the panel's moulded edge looks exactly as it did.
        .background {
            Theme.panel
                .clipShape(panelShape)
                .overlay(InnerShadow(shape: panelShape, scale: deviceScale))
        }
        // Kept even though the inset above means the marker no longer reaches the
        // curve — it's what stops anything in a column spilling past the corners.
        .clipShape(panelShape)
        // Widened past the page gutter to meet the canopy's own edges, so the instrument
        // and the two panels below it line up instead of the panels sitting visibly
        // narrower than the thing they belong to. The columns inside take the extra
        // width themselves — each one is `maxWidth: .infinity`, so they spread rather
        // than leaving a margin.
        .padding(.horizontal, -stripBleed)
    }
}

#Preview("Loaded") {
    WeatherDialScreen(weatherService: PreviewWeatherService(condition: .rain, temperature: 58))
}

// A delay far longer than anyone will sit through, so the preview simply stays in its
// loading state to be looked at: dashes all the way down, and "Updating" under the dial.
#Preview("Loading") {
    WeatherDialScreen(weatherService: PreviewWeatherService(delay: .seconds(600)))
}

#Preview("Failed, nothing to fall back on") {
    WeatherDialScreen(
        weatherService: PreviewWeatherService(error: LocationProvider.LocationError.permissionDenied)
    )
}
