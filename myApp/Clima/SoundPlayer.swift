//
//  SoundPlayer.swift
//  Clima
//

import AVFoundation

/// The app's UI sounds, loaded once at launch and played on demand.
///
/// Views reach this through `SoundPlayer.shared.play(.refresh)` rather than building
/// their own `AVAudioPlayer`, for the same reason they go through `WeatherService`
/// rather than touching WeatherKit: the framework stays in one file, and every sound in
/// the app is decoded once instead of once per tap. Decoding on the tap itself is what
/// makes a UI sound arrive a beat after the finger.
///
/// Failures are all silent. A missing or unreadable file costs the app its sound and
/// nothing else, which is not worth a crash or an error state on screen.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    /// The raw values are the filenames in `Sounds/`, minus the extension.
    enum Sound: String, CaseIterable {
        case refresh = "Refresh_Button"
        case toggle = "Toggle_Switch"
        case wheelClick = "Wheel_Click"
    }

    private var players: [Sound: AVAudioPlayer] = [:]

    private init() {
        // `.ambient` is the category for sounds that decorate an interface rather than
        // being the reason the app is open: it leaves whatever the phone is already
        // playing running, and it lets the ring/silent switch mute these the way it
        // mutes every other UI sound. The default (`.soloAmbient`) would stop the
        // user's music the first time Clima made a sound.
        //
        // The category only — the session isn't activated here. Activating it switches
        // the audio system on, and nothing needs it on until a sound actually plays;
        // `play()` activates it itself at that point.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default)

        for sound in Sound.allCases {
            guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url)
            else { continue }
            // Loaded, but deliberately not `prepareToPlay()`-ed. Preparing takes hold of
            // the audio hardware until that sound has played, and the refresh and toggle
            // sounds often never play in a visit — so preparing them here kept the
            // hardware switched on for as long as the app was open, spending battery on
            // clicks nobody made. `play()` prepares on demand instead, which is what every
            // tap after the first was already doing: a sound gives its preparation back
            // once it finishes.
            players[sound] = player
        }
    }

    /// Plays a sound, restarting it if it's already running.
    ///
    /// One player per sound, so a fast double-tap retriggers from the top rather than
    /// layering two copies over each other — which is how a physical control behaves,
    /// and keeps a jabbed button from building into a drone.
    func play(_ sound: Sound) {
        guard let player = players[sound] else { return }
        player.currentTime = 0
        player.play()
    }
}
