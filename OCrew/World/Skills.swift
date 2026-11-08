import Foundation

enum SkillID: String, CaseIterable, Identifiable {
    case sprint, magnet, scanner, autoSort, freeze

    var id: String { rawValue }

    var name: String {
        switch self {
        case .sprint: return "Sprint"
        case .magnet: return "Magnet"
        case .scanner: return "Scanner"
        case .autoSort: return "Auto-Sort"
        case .freeze: return "Time Freeze"
        }
    }

    var shortName: String {
        switch self {
        case .sprint: return "Sprint"
        case .magnet: return "Magnet"
        case .scanner: return "Scan"
        case .autoSort: return "Sort"
        case .freeze: return "Freeze"
        }
    }

    var symbol: String {
        switch self {
        case .sprint: return "figure.run"
        case .magnet: return "dot.radiowaves.left.and.right"
        case .scanner: return "viewfinder"
        case .autoSort: return "wand.and.stars"
        case .freeze: return "snowflake"
        }
    }

    var cooldown: Double {
        switch self {
        case .sprint: return 15
        case .magnet: return 25
        case .scanner: return 30
        case .autoSort: return 60
        case .freeze: return 75
        }
    }

    var duration: Double {
        switch self {
        case .sprint: return 6
        case .scanner: return 8
        case .freeze: return 10
        default: return 0
        }
    }

    var detail: String {
        switch self {
        case .sprint: return "Move 80% faster for 6 seconds."
        case .magnet: return "Pull nearby items off the floor into your basket."
        case .scanner: return "Light up the signs where your selected item belongs."
        case .autoSort: return "Up to 5 items from your basket fly to their correct spots."
        case .freeze: return "Stop the clock for 10 seconds."
        }
    }
}

struct SkillState {
    var readyAt: Double = 0
    var activeUntil: Double = 0
}

struct SkillSet {
    private(set) var states: [SkillID: SkillState] = [:]

    func isActive(_ s: SkillID, now: Double) -> Bool { (states[s]?.activeUntil ?? 0) > now }
    func isReady(_ s: SkillID, now: Double) -> Bool { (states[s]?.readyAt ?? 0) <= now }

    func cooldownFraction(_ s: SkillID, now: Double, multiplier: Double) -> Double {
        guard let st = states[s], st.readyAt > now else { return 0 }
        return min(1, (st.readyAt - now) / max(0.1, s.cooldown * multiplier))
    }

    func remaining(_ s: SkillID, now: Double) -> Double { max(0, (states[s]?.readyAt ?? 0) - now) }

    mutating func trigger(_ s: SkillID, now: Double, multiplier: Double) {
        states[s] = SkillState(readyAt: now + s.cooldown * multiplier, activeUntil: now + s.duration)
    }

    mutating func reset() { states = [:] }
}
