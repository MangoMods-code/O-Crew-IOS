import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Status colors that adapt to the colorblind setting.
enum StatusPalette {
    static func good(_ m: ColorblindMode) -> UInt32 {
        switch m {
        case .off: return 0x2ECC71
        case .protanopia, .deuteranopia: return 0x0072B2
        case .tritanopia: return 0x009E73
        }
    }
    static func warn(_ m: ColorblindMode) -> UInt32 {
        switch m {
        case .off: return 0xF1C40F
        case .protanopia, .deuteranopia: return 0xF0E442
        case .tritanopia: return 0xF4A6C0
        }
    }
    static func bad(_ m: ColorblindMode) -> UInt32 {
        switch m {
        case .off: return 0xE74C3C
        case .protanopia, .deuteranopia: return 0xD55E00
        case .tritanopia: return 0xD62828
        }
    }
    static func forLevel(_ v: Double, _ m: ColorblindMode) -> UInt32 {
        if v > 0.55 { return good(m) }
        if v > 0.25 { return warn(m) }
        return bad(m)
    }
}

enum Theme {
    static let brand: UInt32 = 0xFF6A1A
    static let brand2: UInt32 = 0xE5322D
    static let panel: UInt32 = 0x14171C
    static let panel2: UInt32 = 0x1F242B
    static let text: UInt32 = 0xF5F6F7
    static let dim: UInt32 = 0x9AA3AD
}

func formatMoney(_ v: Double, symbol: String? = nil) -> String {
    let s = symbol ?? "$"
    let sign = v < 0 ? "-" : ""
    return "\(sign)\(s)\(String(format: "%.2f", abs(v)))"
}
