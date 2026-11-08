import Foundation
import Combine

// MARK: - Option enums

enum CrosshairStyle: String, Codable, CaseIterable, Identifiable {
    case dot, cross, circle, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dot: return "Dot"
        case .cross: return "Cross"
        case .circle: return "Ring"
        case .none: return "Hidden"
        }
    }
}

enum ColorblindMode: String, Codable, CaseIterable, Identifiable {
    case off, protanopia, deuteranopia, tritanopia
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Off"
        case .protanopia: return "Protanopia"
        case .deuteranopia: return "Deuteranopia"
        case .tritanopia: return "Tritanopia"
        }
    }
}

enum JoystickMode: String, Codable, CaseIterable, Identifiable {
    case floating, fixed
    var id: String { rawValue }
    var label: String { self == .floating ? "Floating" : "Fixed" }
}

enum Difficulty: String, Codable, CaseIterable, Identifiable {
    case relaxed, normal, hard, custom
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum FrameRateCap: Int, Codable, CaseIterable, Identifiable {
    case fps30 = 30, fps60 = 60, fps120 = 120
    var id: Int { rawValue }
    var label: String { "\(rawValue) FPS" }
}

enum CrosshairColor: Int, Codable, CaseIterable, Identifiable {
    case white, yellow, cyan, green, magenta
    var id: Int { rawValue }
    var hex: UInt32 {
        switch self {
        case .white: return 0xFFFFFF
        case .yellow: return 0xFFE14D
        case .cyan: return 0x4DE8FF
        case .green: return 0x5CFF7A
        case .magenta: return 0xFF5CE1
        }
    }
    var label: String {
        switch self {
        case .white: return "White"
        case .yellow: return "Yellow"
        case .cyan: return "Cyan"
        case .green: return "Green"
        case .magenta: return "Magenta"
        }
    }
}

// MARK: - Display (UI, camera, readability — no graphics-quality knobs)

struct DisplaySettings: Codable, Equatable {
    // HUD
    var hudScale: Double = 1.0
    var hudOpacity: Double = 0.92
    var textScale: Double = 1.0
    var showTimer = true
    var showRemaining = true
    var showProgressBar = true
    var showPrompts = true
    var showSkillLabels = true
    var showToasts = true
    var showFPS = false
    var basketBarScale: Double = 1.0
    var basketCounts = true
    // World labels
    var showShelfTags = true
    var showRowLabels = true
    var signScale: Double = 1.0
    var highlightFocused = true
    var sparkles = true
    // Crosshair
    var crosshair: CrosshairStyle = .dot
    var crosshairColor: CrosshairColor = .white
    var crosshairSize: Double = 1.0
    // Controls layout
    var leftHanded = false
    var joystickMode: JoystickMode = .floating
    var joystickSize: Double = 1.0
    var buttonSize: Double = 1.0
    var tapToInteract = true
    var holdToRepeat = true
    // Camera
    var fieldOfView: Double = 88
    var lookSensitivity: Double = 1.0
    var lookSensitivityY: Double = 1.0
    var invertY = false
    var headBob = true
    var cameraSmoothing: Double = 0.35
    var frameRate: FrameRateCap = .fps60
    // Accessibility
    var colorblind: ColorblindMode = .off
    var reduceMotion = false
    var highContrastHUD = false
    var haptics = true
    // Audio
    var sfxVolume: Double = 0.8
}

// MARK: - Game rules

struct GameSettings: Codable, Equatable {
    var difficulty: Difficulty = .normal
    var basketCapacity: Double = 10
    var messSize: Double = 1.0
    var placementFeedback = true
    var autoMatch = true
    var keepTogether = true
    var misplacedItems = true
    var expiredItems = true
    var tippedItems = true
    var skillCooldown: Double = 1.0
    var walkSpeed: Double = 1.0
    var parTimeScale: Double = 1.0
    var pickupReach: Double = 2.6
    var showTutorial = true

    mutating func apply(_ preset: Difficulty) {
        difficulty = preset
        switch preset {
        case .relaxed:
            basketCapacity = 15; messSize = 0.7; placementFeedback = true; skillCooldown = 0.7
            walkSpeed = 1.15; parTimeScale = 1.4; pickupReach = 3.0
        case .normal:
            basketCapacity = 10; messSize = 1.0; placementFeedback = true; skillCooldown = 1.0
            walkSpeed = 1.0; parTimeScale = 1.0; pickupReach = 2.6
        case .hard:
            basketCapacity = 8; messSize = 1.25; placementFeedback = false; skillCooldown = 1.3
            walkSpeed = 1.0; parTimeScale = 0.8; pickupReach = 2.3
        case .custom:
            break
        }
    }
}

// MARK: - Store

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var display: DisplaySettings { didSet { save(display, key: Self.displayKey) } }
    @Published var game: GameSettings { didSet { save(game, key: Self.gameKey) } }

    private static let displayKey = "ocrew.display.v2"
    private static let gameKey = "ocrew.game.v2"

    private init() {
        display = Self.load(DisplaySettings.self, key: Self.displayKey, defaults: DisplaySettings())
        game = Self.load(GameSettings.self, key: Self.gameKey, defaults: GameSettings())
    }

    func resetDisplay() { display = DisplaySettings() }
    func resetGame() { game = GameSettings() }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Loads saved settings merged over defaults, so adding new settings never wipes old ones.
    static func load<T: Codable>(_ type: T.Type, key: String, defaults: T) -> T {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let defData = try? JSONEncoder().encode(defaults),
              var merged = (try? JSONSerialization.jsonObject(with: defData)) as? [String: Any]
        else { return defaults }
        for (k, v) in saved where merged[k] != nil { merged[k] = v }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let value = try? JSONDecoder().decode(T.self, from: mergedData)
        else { return defaults }
        return value
    }
}
