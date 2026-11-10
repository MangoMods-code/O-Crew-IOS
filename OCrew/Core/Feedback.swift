import AVFoundation
import UIKit

enum Sound: String, CaseIterable {
    case place, pickup, chime, error, skill, fanfare, ding, bonk, pop, magnet, toss, complete, step
    case section, star, click, whoosh
    case combo1, combo2, combo3, combo4, combo5, combo6, combo7, combo8

    /// A higher note for each combo multiplier (x2…x5).
    static func combo(_ multiplier: Int) -> Sound {
        switch multiplier {
        case ...2: return .combo2
        case 3: return .combo4
        case 4: return .combo6
        default: return .combo8
        }
    }
}

/// Sound effects, music and haptics, respecting the player's settings.
@MainActor
final class Feedback {
    static let shared = Feedback()

    private var pools: [Sound: [AVAudioPlayer]] = [:]
    private var music: AVAudioPlayer?
    private var musicWanted = false
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let notify = UINotificationFeedbackGenerator()

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for s in Sound.allCases {
            guard let url = Bundle.main.url(forResource: s.rawValue, withExtension: "wav") else { continue }
            let copies = s == .step || s == .place || s == .pop ? 3 : 2
            var pool: [AVAudioPlayer] = []
            for _ in 0..<copies {
                if let p = try? AVAudioPlayer(contentsOf: url) {
                    p.prepareToPlay()
                    pool.append(p)
                }
            }
            pools[s] = pool
        }
        if let url = Bundle.main.url(forResource: "music", withExtension: "m4a"), let p = try? AVAudioPlayer(contentsOf: url) {
            p.numberOfLoops = -1
            p.prepareToPlay()
            music = p
        }
    }

    func play(_ sound: Sound, volume: Float = 1) {
        let v = Float(SettingsStore.shared.display.sfxVolume) * volume
        guard v > 0.001, let pool = pools[sound], !pool.isEmpty else { return }
        let player = pool.first(where: { !$0.isPlaying }) ?? pool[0]
        player.currentTime = 0
        player.volume = v
        player.play()
    }

    // MARK: Music

    /// Starts (or keeps) the store-radio loop. Stays silent if the player's own audio is playing.
    func startMusic() {
        musicWanted = true
        applyMusicVolume()
    }

    func stopMusic() {
        musicWanted = false
        music?.setVolume(0, fadeDuration: 0.4)
        let m = music
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            if self?.musicWanted == false { m?.pause() }
        }
    }

    /// Call when the music volume setting changes.
    func applyMusicVolume() {
        guard let m = music else { return }
        let v = Float(SettingsStore.shared.display.musicVolume)
        let othersPlaying = AVAudioSession.sharedInstance().isOtherAudioPlaying
        if musicWanted && v > 0.001 && !(othersPlaying && !m.isPlaying) {
            if !m.isPlaying { m.volume = 0; m.play() }
            m.setVolume(v * 0.6, fadeDuration: 0.6)
        } else if m.isPlaying {
            m.setVolume(0, fadeDuration: 0.3)
            if v <= 0.001 { m.pause() }
        }
    }

    /// Softer while a menu is open over the game.
    func duckMusic(_ ducked: Bool) {
        guard let m = music, m.isPlaying else { return }
        let v = Float(SettingsStore.shared.display.musicVolume) * 0.6
        m.setVolume(ducked ? v * 0.45 : v, fadeDuration: 0.3)
    }

    // MARK: Haptics

    enum Haptic { case light, medium, success, warning, error }

    func haptic(_ h: Haptic) {
        guard SettingsStore.shared.display.haptics else { return }
        switch h {
        case .light: light.impactOccurred()
        case .medium: medium.impactOccurred()
        case .success: notify.notificationOccurred(.success)
        case .warning: notify.notificationOccurred(.warning)
        case .error: notify.notificationOccurred(.error)
        }
    }
}
