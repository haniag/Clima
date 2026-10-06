# Clima

A small SwiftUI weather app built around a circular dial. Weather condition icons sit around the edge of the dial, and a pointer rotates to the one that matches the current weather. Below the dial are an hourly strip and a 7-day forecast.

## Requirements

- Xcode 26 or later
- iOS 18.6 or later
- A paid Apple Developer account if you want to use the WeatherKit source

## Getting started

1. Clone the repo and open `Clima.xcodeproj`.
2. Create `Clima/Secrets.swift`. It's gitignored, so it isn't in the repo:

   ```swift
   enum Secrets {
       /// API key for the Weather Channel source. Leave it empty to use WeatherKit only.
       static let newWeatherAPIKey = ""
   }
   ```

3. In Xcode, select the **Clima** target, open **Signing & Capabilities**, and choose your own team.
4. Build and run.

## Weather sources

The app can read weather from two places. You switch between them on the app's page in the iPhone **Settings** app:

- **Weather Channel**: needs an API key in `Secrets.swift`.
- **WeatherKit** (Apple): needs the WeatherKit capability on your App ID (**Signing & Capabilities → + Capability → WeatherKit**) and a paid developer account.

Either way, the app asks for location permission so it can fetch weather for where you are.

## Project layout

| File | What it does |
| --- | --- |
| `ClimaApp.swift` | App entry point |
| `WeatherDialScreen.swift` | The main screen: loading and error states, the dial, the forecast strips |
| `DialView.swift` | The circular dial and its animated pointer |
| `WeatherCondition.swift` | The fixed set of conditions shown on the dial |
| `WeatherService.swift` | WeatherKit source |
| `NewWeatherService.swift` | Weather Channel source |
| `WeatherSourceSwitch.swift` | Picks the source chosen in Settings |
| `LocationProvider.swift`, `LocationNameService.swift` | Current location and its place name |
| `HourlyForecast.swift`, `DailyForecast.swift`, `HourlyCache.swift` | Forecast models and the hourly cache |
| `Theme.swift` | Colours and type styles |
