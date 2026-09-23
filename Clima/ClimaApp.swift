//
//  ClimaApp.swift
//  Clima
//
//  Created by hani on 4/29/26.
//

import SwiftUI

@main
struct ClimaApp: App {
    /// The live WeatherKit-backed service, built once for the app's lifetime.
    ///
    /// `@State` rather than `let` because a `let` on an `App` is re-evaluated whenever
    /// the body is. That would throw away the service, and with it the
    /// `CLLocationManager` and the geocoded Simulator ZIP it has cached.
    @State private var weatherService = WeatherService()

    var body: some Scene {
        WindowGroup {
            // The one place the app actually measures the screen it's running on.
            // Every fixed size elsewhere — the dial, the panels, every font — was
            // tuned against a 402pt-wide iPhone 16 Pro (`Theme.tunedScreenWidth`) and
            // reads back `deviceScale` (screen width ÷ that number) to scale itself, so
            // the whole layout grows or shrinks together on a narrower iPhone (SE, mini,
            // 375pt) or a wider one (16 Pro Max, 440pt) instead of clipping or floating
            // in unused space.
            GeometryReader { proxy in
                WeatherDialScreen(weatherService: weatherService)
                .environment(\.deviceScale, proxy.size.width / Theme.tunedScreenWidth)
            }
        }
    }
}
