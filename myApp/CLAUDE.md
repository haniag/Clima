# Weather Dial App

## What this app is
A simple iOS weather app whose core interaction is a circular dial. Weather condition icons (sun, cloud, rain, snow, storm, etc.) are arranged around the edge of the dial. A pointer/indicator rotates to point at whichever icon matches the current weather condition. Tapping/dragging is NOT required for v1 — the dial is a *display* mechanic driven by live data, not a user-input control (revisit this if we want history/hourly scrubbing later).

## Who's building this
I'm not a professional software developer — basic coding background, using Claude Code to do most of the implementation. Please:
- Make changes in small, single-purpose steps rather than big multi-file rewrites, so I can follow what changed and why.
- After each change, briefly explain in plain language what you did and why, not just show the diff.
- If something requires a manual step in Xcode (adding a capability, signing, adding a package dependency via Xcode's UI), say so explicitly and tell me exactly where to click.
- Prefer standard SwiftUI/Apple frameworks over third-party dependencies unless there's a clear reason not to.

## Tech stack
- SwiftUI (iOS 18+ target, adjust if needed for WeatherKit availability)
- WeatherKit (Apple's weather API) for live condition + temperature data
- No backend of our own — WeatherKit only, for now

## Core pieces
1. `WeatherService` — wraps WeatherKit, exposes current condition + temperature (and, later, hourly/daily if we expand).
2. `WeatherCondition` — our own enum mapping WeatherKit's condition types to a fixed, ordered set of icons/positions on the dial (e.g. clear,
   partlyCloudy, cloudy, rain, storm, snow, fog). Keep this list small and deliberate — it defines the dial's layout.
3. `DialView` — the circular dial: fixed icons around the circumference, an animated pointer that rotates to the angle matching the current
 condition. Rotation should animate smoothly when the condition changes, not snap instantly.
4. `WeatherDialScreen` — top-level screen: location handling, loading state, error state (no network / WeatherKit denied), and the DialView.

## WeatherKit setup notes (requires manual Xcode/Apple Developer steps)
- Requires a paid Apple Developer account (WeatherKit is not available on free/personal team signing).
- Requires enabling the WeatherKit capability on the App ID in Xcode → Signing & Capabilities.
- Requires location permission (CoreLocation) to fetch weather for the user's current location — add `NSLocationWhenInUseUsageDescription` to
  Info.plist.
- Claude Code should flag when we've reached this point and walk through the exact steps rather than assuming it's already configured.

## Conventions
- SwiftUI previews for every view where feasible, so changes can be checked visually without a full simulator run.
- Keep WeatherKit calls behind `WeatherService` — views should never call WeatherKit directly, so we can swap in mock data for previews/testing.
- Favor `async/await` over completion handlers.

## Not doing yet (don't build ahead of these)
- Multi-day/hourly forecast UI
- Widgets / Live Activities
- watchOS companion
- Location search (current location only for v1)
