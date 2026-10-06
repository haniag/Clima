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
        case failed(String)
    }

    // Shared across every view that reads them (same UserDefaults key), so changing
    // either one here updates the readings immediately. Appearance is applied by this
    // screen's own `.preferredColorScheme` below, rather than up on `ClimaApp`'s
    // WindowGroup, so the Light/Dark switch works in the canvas too.
    @AppStorage("useCelsius") private var useCelsius = false

    /// The Light/Dark switch's setting, or `nil` if it's never been touched — in which
    /// case the app follows the phone's own appearance. A new key rather than the old
    /// `isDarkMode`, which always had a value, so nobody starts out pinned to Light.
    @AppStorage("darkModeOverride") private var darkModeOverride: Bool?

    /// Which weather service answers. Chosen on the app's page in the iPhone's Settings
    /// app and read by `WeatherSourceSwitch` on every fetch; the screen watches it only
    /// to tag the header and to fetch again when it changes.
    @AppStorage(WeatherSource.key) private var weatherSource: WeatherSource = .default

    /// The column at the hourly strip's leading edge. Set to the strip's first column
    /// whenever a reading lands; the reader's swiping moves it in between.
    @State private var hourlyScrollPosition: HourlyStripItem.ID?

    /// Which of the hourly strip's columns is at the middle of its panel right now,
    /// updated continuously while it's swiped — unlike `hourlyScrollPosition`, which only
    /// settles once the strip stops. Drives the 7-day strip's marker; see `markedDay`.
    @State private var hourlyMiddleIndex = 0

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
        .task { await load() }
        // Left in a pocket for an hour, the app would otherwise still be showing the
        // reading it had when it went in there. `.onChange` doesn't fire for the initial
        // value, so this can't double up with the `.task` above on launch — and even if
        // the scene passes through `.inactive` on the way up, `refresh()` declines while
        // that first fetch is still running.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, isReadingStale else { return }
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
    private func refresh() {
        guard status != .loading else { return }
        Task { await load() }
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
    private func load() async {
        fetchGeneration += 1
        let generation = fetchGeneration
        status = .loading

        do {
            let reading = try await weatherService.currentWeather()
            // Somebody started a newer fetch while this one was out. Their answer is the
            // one that should win, so this one retires quietly.
            guard generation == fetchGeneration else { return }
            snapshot = reading
            status = .ready
        } catch {
            guard generation == fetchGeneration else { return }
            // A cancelled fetch isn't a failed one — the screen is going away, or a newer
            // request replaced this one. Reporting it would put an error under a dial
            // nobody is looking at, and leave it there.
            if error is CancellationError || Task.isCancelled { return }
            // Never `error.localizedDescription` straight to the screen — see
            // `WeatherErrorMessage`, which picks the sentence a reader can act on and
            // sends the raw error to the console instead.
            status = .failed(WeatherErrorMessage.text(for: error))
        }
    }

    private var page: some View {
        ScrollView {
            VStack(spacing: Theme.blockGap * deviceScale) {
                header

                // Passed through as an optional: with no reading the dial highlights
                // nothing, rather than sitting lit on `.clear` and telling the reader it's
                // sunny out while the readout underneath says there's no reading.
                DialView(condition: snapshot?.condition, onRefresh: refresh)
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
                    strip {
                        // Worked out once here rather than per column: it rebuilds the
                        // hourly strip's list of columns to find the one in the middle.
                        let marked = markedDay
                        ForEach(snapshot?.daily ?? .placeholder()) { day in
                            ForecastDayColumn(
                                day: day,
                                isMarked: Calendar.current.isDate(day.date, inSameDayAs: marked)
                            )
                        }
                    }

                    hourlyStrip
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
            // no more room above it than the hourly one leaves under the 7-day. (It's
            // pinned to the bottom, so any spare height on a taller phone lands here.)
            .padding(.bottom, SettingsDrawer.height(scale: deviceScale)
                + SettingsDrawer.bottomMargin(scale: deviceScale)
                + Theme.stripGap * deviceScale)
        }
        // Only scroll when the content genuinely doesn't fit: on a large phone the page
        // should sit still, not bounce.
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            // Where the reading is for. `climaCaps` uppercases it, so this reads
            // "CENTREVILLE" on screen. Blank until a name is known — a space rather than
            // nothing, so the header keeps its height and nothing below it jumps when the
            // name arrives. One line, cut short with an ellipsis, so a long place name
            // can't push the "Updated" time onto a second line.
            Text(snapshot?.locationName ?? " ")
                .climaCaps(.caption, bold: true)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)

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

            if case .failed(let message) = status {
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

    /// "Updated 14:32", or nil when there's no reading to date.
    ///
    /// The day is added once the reading is no longer from today — which happens if the
    /// app is left open overnight — because a bare "04:15" on a reading twelve hours old
    /// looks exactly like one from four minutes ago.
    private var updatedLabel: String? {
        guard let snapshot else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(snapshot.fetchedAt)
            ? "HH:mm"
            : "EEE d MMM HH:mm"
        return "Updated \(formatter.string(from: snapshot.fetchedAt))"
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

    /// Precipitation in the last hour, above humidity — whichever of the two the
    /// reading has. Empty with no reading, so the dash under the dial stays centred.
    ///
    /// Leading-aligned so the two icons line up in a column and the numbers start at the
    /// same place.
    @ViewBuilder
    private var sideReadings: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 4 * deviceScale) {
                if let precipitation = snapshot.precipitationLastHour {
                    sideReading(
                        icon: "precipitation",
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
                    sideReading(icon: "humidity", value: "\(humidity)%")
                        .accessibilityLabel("Humidity \(humidity) percent")
                }
            }
        }
    }

    private func sideReading(icon: String, value: String) -> some View {
        HStack(spacing: 2 * deviceScale) {
            Image(icon)
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
    /// longer differ in colour. The 7-day strip marks today; the hourly strip marks its
    /// first column.
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
    /// `scrollHourlyToStart()`. The 7-day strip's marker follows the day being swiped
    /// through — see `markedDay`.
    private var hourlyStrip: some View {
        stripPanel {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    let items = visibleStripItems
                    ForEach(items) { item in
                        // The first column carries the "now" marker: it's the one
                        // closest to now, whether an hour or a sunrise or sunset.
                        let isFirst = item.id == items.first?.id
                        Group {
                            switch item {
                            case .hour(let hour):
                                HourlyColumn(hour: hour, isMarked: isFirst)
                            case .sun(let event):
                                SunEventColumn(event: event, isMarked: isFirst)
                            }
                        }
                        .containerRelativeFrame(.horizontal, count: 8, spacing: 0)
                    }
                }
                .scrollTargetLayout()
            }
            // Margins rather than padding, so a column swiped past them still shows right
            // out to the panel's edge, while a column at rest sits `stripInset` in, clear
            // of the corners the same as the 7-day strip's.
            .contentMargins(.horizontal, stripInset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $hourlyScrollPosition, anchor: .leading)
            // Which column has reached the middle of the panel, read continuously while
            // the strip moves, so the 7-day marker follows mid-swipe — see `markedDay`.
            // It's the last column whose own centre has reached or passed the panel's
            // centre: tomorrow's 12AM counts once it's swiped to the middle, and stops
            // counting once it's swiped back past it.
            //
            // Every column is the same width, so the content's width shared out between
            // them gives that width. The content's own coordinates start at the first
            // column's leading edge, and `contentOffset` is where the panel's left edge
            // sits in them, so half the panel's width on from it is its centre. The
            // panel's width is the container's plus the side margins, which
            // `containerSize` leaves out.
            .onScrollGeometryChange(for: Int.self) { geometry in
                let count = visibleStripItems.count
                guard count > 0, geometry.contentSize.width > 0 else { return 0 }
                let columnWidth = geometry.contentSize.width / CGFloat(count)
                let panelWidth = geometry.containerSize.width
                    + geometry.contentInsets.leading + geometry.contentInsets.trailing
                let panelCentre = geometry.contentOffset.x + panelWidth / 2
                let index = Int((panelCentre / columnWidth - 0.5).rounded(.down))
                return min(max(index, 0), count - 1)
            } action: { _, index in
                hourlyMiddleIndex = index
            }
        }
        .onAppear(perform: scrollHourlyToStart)
        .onChange(of: snapshot?.fetchedAt) { scrollHourlyToStart() }
    }

    /// Brings the strip back to its first column when the screen appears and whenever a
    /// new reading lands, so a refresh also puts what's next back where it's expected.
    private func scrollHourlyToStart() {
        hourlyScrollPosition = visibleStripItems.first?.id
    }

    /// The day the 7-day strip marks: the day of the column at the middle of the hourly
    /// panel. Swiping tomorrow's 12AM to the middle and beyond moves the marker above onto
    /// tomorrow, and swiping it back past the middle brings the marker home.
    private var markedDay: Date {
        let items = visibleStripItems
        guard items.indices.contains(hourlyMiddleIndex) else { return Date() }
        return items[hourlyMiddleIndex].id.date
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
    private var visibleStripItems: [HourlyStripItem] {
        let now = Date()
        let firstHour = [HourlyForecast].stripStart(after: now)
        var hours = (snapshot?.hourly ?? .placeholder()).filter { $0.date >= firstHour }
        // A reading so old that none of its hours are left: show empty slots instead.
        if hours.isEmpty {
            hours = .placeholder()
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

// MARK: - Forecast columns

/// The width every value's icon and "now" marker are sized to, at `deviceScale` 1 (the
/// iPhone 16 Pro this was tuned on).
///
/// Measured from the rendered app rather than guessed: the temperature text is ~24pt
/// wide at its font, but the condition icons — measured the same way, glyph edge to
/// glyph edge — only fill about half of their old 26pt frame, so *nominally* matching
/// the number's width left them looking much smaller than it. 41pt is about as far as
/// that can be pushed before it outgrows what's actually available: the hourly strip's
/// 8 columns leave ~41.5pt each inside the panel, the tightest of the two rows, so this
/// is at the ceiling rather than a true pixel match to the number. Scaling this
/// alongside the panel it sits in keeps that same tight-but-fitting relationship on
/// every iPhone rather than just the one it was measured on.
private let baseStripContentWidth: CGFloat = 41

/// The corner radius of a forecast panel, at `deviceScale` 1. Shared with the settings
/// drawer, whose open state is meant to be indistinguishable from one of these panels —
/// one number, so the two can't drift apart.
private let baseStripCornerRadius: CGFloat = 18

/// One column in the 7-day strip: weekday letter, condition icon, high, low, and the
/// chance of precipitation.
private struct ForecastDayColumn: View {
    let day: DailyForecast
    /// Whether this column carries the marker: the day the hourly strip below is
    /// showing — see `markedDay`. Today, until the hours are swiped into another day.
    let isMarked: Bool

    @AppStorage("useCelsius") private var useCelsius = false
    @Environment(\.deviceScale) private var deviceScale

    var body: some View {
        StripColumn(isActive: isMarked) {
            Text(day.dayLetter)
                .climaCaps(.heading)
                .foregroundStyle(Theme.panelInk)

            // No condition, no icon — a guessed one would be as misleading as a guessed
            // number. The empty frame keeps every column's rows on the same baselines, so
            // the strip doesn't jump when a reading finally lands.
            Group {
                if let condition = day.condition {
                    Image(condition.iconName)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Theme.panelIcon)
                } else {
                    Color.clear
                }
            }
            .frame(width: baseStripContentWidth * deviceScale, height: baseStripContentWidth * deviceScale)

            // Regular even for today: the marker above the column already says which day
            // is today, and a bold high read as heavier than the rest of the row.
            Text(temperatureText(day.highTemp, useCelsius: useCelsius))
                .font(Theme.valueFont(scale: deviceScale))
                .foregroundStyle(Theme.panelInk)

            Text(temperatureText(day.lowTemp, useCelsius: useCelsius))
                .font(Theme.valueFont(scale: deviceScale))
                .foregroundStyle(Theme.panelInkMuted)

            // Only a likely chance is shown: seven small percentages, most of them near
            // zero, read as noise. The condition icon above already says what's coming,
            // so the number needs no drop icon beside it.
            Text(precipitationChanceText(day.precipitationChance))
                .font(Theme.valueFont(scale: deviceScale))
                .foregroundStyle(Theme.panelInkMuted)
        }
    }
}

/// Chances at or below this show as a dash rather than a number, on both strips.
private let precipitationThreshold = 40

/// The chance as "75%" when it's above the threshold, and "—" otherwise — whether it's
/// too low to bother with or there's no reading yet.
private func precipitationChanceText(_ chance: Int?) -> String {
    guard let chance, chance > precipitationThreshold else {
        return "—"
    }
    return "\(chance)%"
}

/// One column in the hourly strip: the hour, condition icon, temperature, and the
/// chance of precipitation.
private struct HourlyColumn: View {
    let hour: HourlyForecast
    /// Whether this column carries the "now" marker — see `hourlyStrip`.
    let isMarked: Bool

    @AppStorage("useCelsius") private var useCelsius = false
    @Environment(\.deviceScale) private var deviceScale

    var body: some View {
        StripColumn(isActive: isMarked) {
            // Midnight is "12AM" like any other hour; the 7-day strip's marker is what
            // says which day the strip has reached.
            Text(hour.timeLabel)
                .climaCaps(.heading)
                .foregroundStyle(Theme.panelInk)

            // Same as the 7-day column: no condition means no icon, but the frame stays
            // so the hours keep their rows aligned.
            Group {
                if let condition = hour.condition {
                    Image(condition.iconName)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Theme.panelIcon)
                } else {
                    Color.clear
                }
            }
            .frame(width: baseStripContentWidth * deviceScale, height: baseStripContentWidth * deviceScale)

            Text(temperatureText(hour.temperature, useCelsius: useCelsius))
                .font(Theme.valueFont(scale: deviceScale))
                .foregroundStyle(Theme.panelInk)

            // Same rule as the 7-day column: only a likely chance gets a number.
            Text(precipitationChanceText(hour.precipitationChance))
                .font(Theme.valueFont(scale: deviceScale))
                .foregroundStyle(Theme.panelInkMuted)
        }
    }
}

/// One column on the hourly strip: an hour, or a sunrise or sunset between two of them.
private enum HourlyStripItem: Identifiable {
    case hour(HourlyForecast)
    case sun(SunEvent)

    /// What the strip's scroll position is kept in. Built from the hour's start or the
    /// event itself rather than `HourlyForecast.id`, because every reading makes new ids
    /// and the scroll position has to survive from one to the next.
    enum ID: Hashable {
        case hour(Date)
        case sun(SunEvent)

        /// When the column is: the hour's start, or the event's moment.
        var date: Date {
            switch self {
            case .hour(let date): date
            case .sun(let event): event.date
            }
        }
    }

    var id: ID {
        switch self {
        case .hour(let hour): .hour(hour.date)
        case .sun(let event): .sun(event)
        }
    }

    /// Orders the columns by time. A sunrise or sunset at exactly the top of an hour
    /// goes after that hour's column, the same as one a minute later would.
    var sortKey: (Date, Int) {
        switch self {
        case .hour(let hour): (hour.date, 0)
        case .sun(let event): (event.date, 1)
        }
    }
}

/// A sunrise or sunset column on the hourly strip: the time it happens, to the minute,
/// over its icon. The temperature and rain-chance rows are left empty — there's no
/// forecast for a moment, only for an hour.
private struct SunEventColumn: View {
    let event: SunEvent
    /// Whether this column carries the "now" marker — see `hourlyStrip`.
    let isMarked: Bool

    @Environment(\.deviceScale) private var deviceScale

    var body: some View {
        StripColumn(isActive: isMarked) {
            Text(event.timeLabel)
                .climaCaps(.heading)
                .foregroundStyle(Theme.panelInk)

            // The artwork fills nearly its whole canvas, where the condition icons only
            // fill about half of theirs (see `baseStripContentWidth`), so it's drawn at a
            // bit over half the frame to come out the same size as its neighbours. The
            // outer frame matches theirs so the rows below stay on the same baselines.
            Image(event.iconName)
                .resizable()
                .scaledToFit()
                .frame(width: baseStripContentWidth * 0.55 * deviceScale)
                .frame(width: baseStripContentWidth * deviceScale, height: baseStripContentWidth * deviceScale)

            // Held open but not shown, so the column is as tall as the hours either side.
            Text("—")
                .font(Theme.valueFont(scale: deviceScale))
                .hidden()
            Text("—")
                .font(Theme.valueFont(scale: deviceScale))
                .hidden()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.accessibilityLabel)
    }
}

/// The shared shell for both strips: an equal-width column topped by the "now" marker,
/// which is always laid out but only visible on the active column, so every column in a
/// row keeps its contents on the same baselines.

private struct StripColumn<Content: View>: View {
    let isActive: Bool
    @ViewBuilder let content: Content

    @Environment(\.deviceScale) private var deviceScale

    var body: some View {
        VStack(spacing: 0) {
            // The same triangle-and-line index mark the dial's pointer uses, shrunk
            // down: one shape, one colour, one meaning throughout the app.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.indexMark)
                    .frame(width: baseStripContentWidth * deviceScale, height: 4 * deviceScale)

                Triangle()
                    .fill(Theme.indexMark)
                    .frame(width: 16 * deviceScale, height: 7 * deviceScale)
            }
            .opacity(isActive ? 1 : 0)
            // A quick cross-fade when the marker moves — on the 7-day strip it follows
            // the hourly strip's swiping from one day to the next.
            .animation(.easeInOut(duration: 0.2), value: isActive)

            VStack(spacing: 7 * deviceScale) {
                content
            }
            // Measured from the marker's slot, so the triangle's tip still clears the
            // heading beneath it.
            .padding(.top, 6 * deviceScale)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Settings drawer

/// The two switches, kept behind a plain rectangular cover that slides out of the way.
///
/// The knurling near the cover's right end is the finger grip, and the only thing on
/// the closed row that invites a touch. Touching it slides the cover left; it stops
/// with just that grip still showing at the left end, so the same texture that opened
/// the drawer is what's under the finger to close it again.
///
/// The cover doesn't fill the row — it sits in it with `gap` of clearance on every
/// side, and the recess showing through that clearance is what draws the seam around
/// it. A real gap rather than a line stroked onto the cover, because a stroke only
/// exists where the cover does: slid open, its left end is cut off by the clip, and a
/// stroked outline would leave the parked grip with a seam on three sides and a raw
/// edge on the fourth.
///
/// The switches don't move between the two states — they sit permanently inset past
/// where the parked grip ends, and the cover slides over them — so nothing jumps
/// sideways as the drawer opens.
private struct SettingsDrawer: View {
    @Binding var useCelsius: Bool
    @Binding var isDarkMode: Bool

    @Environment(\.deviceScale) private var deviceScale
    @State private var isOpen = false

    /// Static as well as an instance property, because the page above reserves exactly
    /// this much room to scroll behind, and the two mustn't drift apart.
    static func height(scale: CGFloat) -> CGFloat { 56 * scale }

    /// How far the bar floats above the screen's physical bottom edge.
    ///
    /// This is what keeps the corners honest. Run flush to the edge, the display's own
    /// ~55-62pt corner curve cuts across the bar's 18pt corners and swallows the 3pt seam
    /// entirely at both ends — the screen's bottom is not a rectangle, and there's no
    /// public API for its radius to match against. Held `gutter` clear of that edge and
    /// the same distance in from the sides as the forecast panels, the bar's corners stay
    /// well inside the curve on every iPhone, and the seam reads evenly the whole way
    /// round in both states.
    static func bottomMargin(scale: CGFloat) -> CGFloat { Theme.gutter * scale }

    /// The forecast panels' width, so the bar lines up with them and with the canopy.
    private var width: CGFloat { DialView.canopyWidth(scale: deviceScale) }
    private var height: CGFloat { Self.height(scale: deviceScale) }
    /// How much cover stays on screen once it's open: enough to hold the whole knurled
    /// grip, and with it the way back.
    ///
    /// Back to 44 now that the bar is its tuned height again — it was only widened to 60
    /// to keep the parked block from reading as a tall thin tab when the bar stretched
    /// down to the screen's edge, and that's no longer the shape it has to balance.
    private var gripWidth: CGFloat { 44 * deviceScale }
    /// The clearance between the cover and the recess it rides in, on all four sides.
    private var gap: CGFloat { 3 * deviceScale }
    /// Concentric with the slot's rather than a value of its own: exactly one `gap`
    /// smaller, so the seam between cover and recess holds the same width round the
    /// corners as it does along the straight edges. At the old flat 10 against the slot's
    /// 18 the two curves weren't concentric, and the seam quietly fattened at all four.
    private var coverRadius: CGFloat { baseStripCornerRadius * deviceScale - gap }

    /// The cover is the row less its clearance, so `travel` — and the grip left behind
    /// at the end of it — are both measured against the cover's own width.
    private var coverWidth: CGFloat { width - 2 * gap }
    private var coverHeight: CGFloat { height - 2 * gap }
    private var travel: CGFloat { coverWidth - gripWidth }

    private var coverShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: coverRadius, style: .continuous)
    }

    private var ridgesWidth: CGFloat { GripRidges.width(scale: deviceScale) }

    /// The drawer's outline — the forecast panels' shape, to the point of sharing their
    /// corner radius. Rounded on all four corners again now that the bar floats clear of
    /// the screen's edge and has four corners of its own to show.
    private var slotShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: baseStripCornerRadius * deviceScale, style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Background, rounding and shading applied in the same order `strip` uses,
            // so what the cover slides off to reveal is indistinguishable from one of
            // the forecast panels above it — shadow falling across the switches
            // included, exactly as it falls across the forecast columns.
            switches
                // Faded rather than merely covered, so a switch can't show through the
                // clearance around the cover while the drawer is shut. The opacity sits
                // above the background deliberately: the recess itself stays visible in
                // both states, and it's what fills the seam around the cover.
                .opacity(isOpen ? 1 : 0)
                .allowsHitTesting(isOpen)
                .frame(width: width, height: height)
                .background(Theme.panel)
                .clipShape(slotShape)
                .overlay(InnerShadow(shape: slotShape, scale: deviceScale))

            coverLayer
        }
        .frame(width: width, height: height)
    }

    /// The cover, and the window it slides within.
    ///
    /// `offset` moves the cover without moving the frame around it, so the clip cuts it
    /// at that frame's edge — and since `padding` holds the frame `gap` in from the row,
    /// the open state keeps its clearance on the left exactly as the closed state has it
    /// on the right.
    ///
    /// The clip is `coverShape`, not a plain rectangle. A rectangular one left the parked
    /// grip with two square corners at its cut end, and those sat outside the recess's own
    /// rounded corner — the cover visibly spilled out of the slot it's supposed to ride
    /// in. Clipping to the same rounded shape trims the parked end to the recess's curve
    /// instead, and costs nothing when the drawer is shut, since the cover is that shape
    /// already.
    private var coverLayer: some View {
        cover
            .offset(x: isOpen ? -travel : 0)
            .frame(width: coverWidth, height: coverHeight, alignment: .leading)
            .clipShape(coverShape)
            .padding(gap)
    }

    private var switches: some View {
        HStack {
            SlideToggle(leading: "°F", trailing: "°C", tracked: false, isTrailing: $useCelsius)
            Spacer()
            SlideToggle(leading: "Light", trailing: "Dark", isTrailing: $isDarkMode)
        }
        // Clear of where the parked cover ends — its own `gap` inset included, since
        // the switches are measured from the row's edge and the cover isn't.
        .padding(.leading, gap + gripWidth + 10 * deviceScale)
        // The row reaches the screen's own edge now, so the last label needs a real
        // margin rather than just enough to clear a rounded corner.
        .padding(.trailing, 20 * deviceScale)
    }

    private var cover: some View {
        coverShape
            // Page colour, not a surface tone: closed, the cover is meant to sit flush
            // and near-invisible, leaving only the seam around it and the knurling to
            // say there's anything here at all.
            .fill(Theme.canvas)
            .frame(width: coverWidth, height: coverHeight)
            // The knurling — the same texture the toggle knobs wear, and now the only
            // thing marking the grip. Centred in the width that stays on screen when
            // the drawer is open, so the finger lands on it in both states. Held at
            // reduced strength because the cover is page colour, pale enough that
            // full-contrast lines would read as a printed barcode rather than a
            // texture.
            .overlay(alignment: .trailing) {
                GripRidges(height: 18 * deviceScale, strength: 0.85, scale: deviceScale)
                    .padding(.trailing, (gripWidth - ridgesWidth) / 2)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    isOpen.toggle()
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isOpen ? "Hide settings" : "Show settings")
    }
}

// MARK: - Controls

/// A two-position slide switch, built to look like the hardware kind: a channel milled
/// into the panel, and a raised, knurled slab riding in it between two engraved detent
/// marks.
///
/// Four things do the work, all of them lit from above like the rest of the app's
/// moulded surfaces (`InnerShadow`):
/// - The channel is its own tone (`Theme.toggleTrack`), darker than the panel it's cut
///   into, and squared off rather than a capsule. A capsule of the panel's own colour
///   reads as a pill drawn on the surface; a darker rounded rectangle reads as a hole
///   in it.
/// - The knob is a slab, not a disc — filled with a top-to-bottom gradient and rimmed
///   with a bright top edge falling to a dark bottom one, so it has a visible thickness
///   standing proud of the channel.
/// - It carries `GripRidges`, the same knurling as the drawer's cover. This is the part
///   that says *this* is the bit to push, rather than leaving a smooth lozenge that
///   could as easily be a progress indicator.
/// - A tick beside each end marks where the knob stops, and brightens with the label on
///   the side it's resting against — the detent marks on the reference panel.
///
/// The words ("°F"/"°C", "Light"/"Dark") stay outside the channel rather than being
/// printed on the knob, which is how a panel switch is labelled and also what lets the
/// label itself be a tap target.
private struct SlideToggle: View {
    let leading: String
    let trailing: String
    /// Word labels want the tracked-out treatment the rest of the app uses; a unit like
    /// "°F" does not — spacing it out reads as "° F".
    var tracked = true
    @Binding var isTrailing: Bool

    @Environment(\.deviceScale) private var deviceScale

    /// Wider than it is tall, along the direction of travel: the proportion of a thumb
    /// slide rather than of a button.
    private var knobWidth: CGFloat { 28 * deviceScale }
    private var knobHeight: CGFloat { 22 * deviceScale }
    /// The gap between knob and channel wall. Small — a machined fit, not a loose one.
    private var padding: CGFloat { 3 * deviceScale }
    private var trackHeight: CGFloat { knobHeight + 2 * padding }
    /// How far the knob throws. A shade under its own width: plenty for the two
    /// positions to be unmistakable at a glance, and no more — this row carries two
    /// switches and four labels, and a longer channel pushes "DARK" off the panel's
    /// right edge, where the drawer's clip cuts it in half.
    private var travel: CGFloat { 22 * deviceScale }
    private var trackWidth: CGFloat { knobWidth + travel + 2 * padding }

    /// Rounded, but well short of a capsule — the channel should keep its corners.
    private var trackShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8 * deviceScale, style: .continuous)
    }
    /// A touch tighter than the channel's, so the knob looks like a part machined to
    /// drop into it rather than a shape scaled down from it.
    private var knobShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 6 * deviceScale, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 4 * deviceScale) {
            label(leading, isSelected: !isTrailing) { isTrailing = false }
            tick(isSelected: !isTrailing)
            track
            tick(isSelected: isTrailing)
            label(trailing, isSelected: isTrailing) { isTrailing = true }
        }
    }

    private func label(_ title: String, isSelected: Bool, select: @escaping () -> Void) -> some View {
        Text(title)
            .climaCaps(.small, tracked: tracked)
            .foregroundStyle(isSelected ? Theme.ink : Theme.inkMuted)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { select() } }
    }

    /// The detent mark between a label and the end of the channel. Deliberately faint
    /// when it isn't the live one: two marks of equal weight would read as decoration,
    /// where one bright and one dim reads as a position indicator.
    private func tick(isSelected: Bool) -> some View {
        Capsule()
            .fill(isSelected ? Theme.ink : Theme.inkMuted.opacity(0.4))
            .frame(width: 4 * deviceScale, height: deviceScale)
    }

    private var track: some View {
        trackShape
            .fill(Theme.toggleTrack)
            .frame(width: trackWidth, height: trackHeight)
            // Colour alone only makes it a dark shape; the shading is what gives the
            // channel a lip and a floor, and so a depth. Tightened well in from the
            // default `spread`, which is sized for the forecast panels — at full width
            // it washes across a channel this narrow instead of hugging its edge.
            .overlay(InnerShadow(shape: trackShape, opacity: 0.3, spread: 5, scale: deviceScale))
            .overlay(alignment: isTrailing ? .trailing : .leading) {
                knob.padding(padding)
            }
            .contentShape(trackShape)
            .onTapGesture {
                SoundPlayer.shared.play(.toggle)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isTrailing.toggle() }
            }
    }

    /// The raised knob: a top-lit gradient face carrying the grip knurling, a bevel
    /// stroked round the rim (bright at the top, dark at the bottom) to give it an
    /// edge, and a drop shadow cast down into the channel so it sits *above* the panel
    /// rather than flush in it.
    private var knob: some View {
        knobShape
            .fill(
                LinearGradient(
                    colors: [Theme.toggleKnob, Theme.toggleKnobShade],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: knobWidth, height: knobHeight)
            // Well short of the knob's full height, and tighter together than the
            // drawer cover's: the grooves have to read as one patch of knurling on a
            // face this small, where at full spacing and height they separate into
            // three bars and start looking like an icon.
            .overlay(GripRidges(height: knobHeight * 0.38, spacing: 2.5, scale: deviceScale))
            .overlay(
                knobShape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.9), .white.opacity(0.06), .black.opacity(0.2)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: deviceScale
                )
            )
            // Straight down, not down-and-right: everything else on the page is lit from
            // directly above, and an offset shadow here would light this one control
            // from a different sun.
            .shadow(color: .black.opacity(0.3), radius: 2 * deviceScale, y: 1.5 * deviceScale)
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
