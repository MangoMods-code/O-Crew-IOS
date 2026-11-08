import Foundation

enum SkillID: String, CaseIterable, Identifiable {
    case sprint, rushRestock, expressScan, crowdCalm, eagleEye

    var id: String { rawValue }

    var name: String {
        switch self {
        case .sprint: return "Sprint"
        case .rushRestock: return "Rush Restock"
        case .expressScan: return "Express Scan"
        case .crowdCalm: return "Crowd Calm"
        case .eagleEye: return "Eagle Eye"
        }
    }

    var shortName: String {
        switch self {
        case .sprint: return "Sprint"
        case .rushRestock: return "Restock"
        case .expressScan: return "Express"
        case .crowdCalm: return "Calm"
        case .eagleEye: return "Eagle"
        }
    }

    var symbol: String {
        switch self {
        case .sprint: return "figure.run"
        case .rushRestock: return "shippingbox.fill"
        case .expressScan: return "barcode.viewfinder"
        case .crowdCalm: return "face.smiling"
        case .eagleEye: return "eye.fill"
        }
    }

    var cooldown: Double {
        switch self {
        case .sprint: return 18
        case .rushRestock: return 35
        case .expressScan: return 45
        case .crowdCalm: return 90
        case .eagleEye: return 60
        }
    }

    var duration: Double {
        switch self {
        case .sprint: return 6
        case .eagleEye: return 12
        default: return 0
        }
    }

    var detail: String {
        switch self {
        case .sprint: return "Move 80% faster for 6 seconds."
        case .rushRestock: return "Instantly fill the shelf you're looking at from the box you're holding."
        case .expressScan: return "Scan every item on the counter at once."
        case .crowdCalm: return "Every customer's patience refills to full."
        case .eagleEye: return "Shoplifters glow red for 12 seconds."
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

    /// 0 = ready, 1 = just used.
    func cooldownFraction(_ s: SkillID, now: Double, multiplier: Double) -> Double {
        guard let st = states[s], st.readyAt > now else { return 0 }
        return min(1, (st.readyAt - now) / (s.cooldown * multiplier))
    }

    func remaining(_ s: SkillID, now: Double) -> Double { max(0, (states[s]?.readyAt ?? 0) - now) }

    mutating func trigger(_ s: SkillID, now: Double, multiplier: Double) {
        states[s] = SkillState(readyAt: now + s.cooldown * multiplier, activeUntil: now + s.duration)
    }

    mutating func reset() { states = [:] }
}
