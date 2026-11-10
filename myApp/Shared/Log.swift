//
//  Log.swift
//  Clima
//
//  Compiled into both the app and the widget extension.
//

import os

/// Where the app writes what went wrong, for whoever is debugging it.
///
/// `Logger` rather than `print`, because `print` only reaches Xcode's console while the
/// app is running from Xcode. A `Logger` message is kept by the phone itself, so it can
/// still be read afterwards in the Console app — filter by the subsystem below — which
/// is the only way to see why the lock screen widget's fetch failed, since the widget
/// never runs attached to Xcode in normal use.
///
/// One category per part of the app, so the Console can be narrowed to just that part.
///
/// `nonisolated` because both targets put code on the main actor by default, and these
/// are written to from off it.
nonisolated enum Log {
    private static let subsystem = "com.fursa.Clima"

    /// Fetching the weather, from either service.
    static let weather = Logger(subsystem: subsystem, category: "weather")
    /// Finding where the phone is, what that place is called, and searching for others.
    static let location = Logger(subsystem: subsystem, category: "location")
    /// The lock screen widget's own fetches.
    static let widget = Logger(subsystem: subsystem, category: "widget")
}
