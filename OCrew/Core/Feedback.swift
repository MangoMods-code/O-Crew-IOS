import AVFoundation
import UIKit

enum Sound: String, CaseIterable {
    case place, pickup, chime, error, skill, fanfare, ding, bonk, pop, magnet, toss, complete
}

/// Sound effects + haptics, respecting the player's settings.
@MainActor
final class Feedback {
    static let shared = Feedback()

    private var pools: [Sound: [AVAudioPlayer]] = [:]
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let notify = UINotificationFeedbackGenerator()

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for s in Sound.allCases {
            guard let url = Bundle.main.url(forResource: s.rawValue, withExtension: "wav") else { continue }
            var pool: [AVAudioPlayer] = []
            for _ in 0..<3 {
                if let p = try? AVAudioPlayer(contentsOf: url) {
                    p.prepareToPlay()
                    pool.append(p)
                }
            }
            pools[s] = pool
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
