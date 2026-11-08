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

enum DeliverySpeed: String, Codable, CaseIterable, Identifiable {
    case instant, fast, normal
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var seconds: Double {
        switch self {
        case .instant: return 0
        case .fast: return 4
        case .normal: return 12
        }
    }
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
    var showClock = true
    var use24hClock = false
    var showMoney = true
    var showRating = true
    var showPrompts = true
    var showSkillLabels = true
    var showMoneyPopups = true
    var showToasts = true
    var showFPS = false
    var currencySymbol = "$"
    // World labels
    var showPriceTags = true
    var showPatienceBars = true
    var highlightFocused = true
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
    var holdToRepeatStock = true
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
    var dayLengthMinutes: Double = 10
    var customerRate: Double = 1.0
    var customerPatience: Double = 1.0
    var priceSensitivity: Double = 1.0
    var theftRate: Double = 1.0
    var startingCash: Double = 1.0
    var rentMultiplier: Double = 1.0
    var skillCooldown: Double = 1.0
    var walkSpeed: Double = 1.0
    var delivery: DeliverySpeed = .fast
    var manualChange = true
    var showChangeDue = true
    var cashCustomerShare: Double = 0.45
    var autoDiscardEmptyBoxes = true
    var finishShoppersAtClose = true
    var showTutorial = true
    var outOfStockPenalty = true

    mutating func apply(_ preset: Difficulty) {
        difficulty = preset
        switch preset {
        case .relaxed:
            dayLengthMinutes = 14; customerRate = 0.8; customerPatience = 1.6; priceSensitivity = 0.7
            theftRate = 0.4; startingCash = 1.5; rentMultiplier = 0.6; skillCooldown = 0.7; delivery = .instant
        case .normal:
            dayLengthMinutes = 10; customerRate = 1.0; customerPatience = 1.0; priceSensitivity = 1.0
            theftRate = 1.0; startingCash = 1.0; rentMultiplier = 1.0; skillCooldown = 1.0; delivery = .fast
        case .hard:
            dayLengthMinutes = 8; customerRate = 1.3; customerPatience = 0.7; priceSensitivity = 1.4
            theftRate = 1.8; startingCash = 0.8; rentMultiplier = 1.3; skillCooldown = 1.3; delivery = .normal
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

    private static let displayKey = "ocrew.display.v1"
    private static let gameKey = "ocrew.game.v1"

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
