import AppKit
import IslandCore

enum CueSound: String, CaseIterable, Identifiable, Sendable {
    case off = "off"
    case basso = "Basso"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case glass = "Glass"
    case hero = "Hero"
    case morse = "Morse"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"

    var id: String { rawValue }
    var displayName: String { self == .off ? "无" : rawValue }
    var systemName: String? { self == .off ? nil : rawValue }
}

@MainActor
enum AlertSoundPlayer {
    private static var playing: [NSSound] = []

    static func play(_ cue: AlertCue) {
        play(IslandSettings.sound(for: cue))
    }

    static func play(_ sound: CueSound) {
        guard let name = sound.systemName else { return }
        for active in playing { active.stop() }
        playing.removeAll()
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            NSSound.beep()
            return
        }
        sound.play()
        playing.append(sound)
    }
}
