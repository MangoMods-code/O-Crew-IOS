import Foundation

/// Launch arguments used by the automated screenshot run (CI): `-shot <levelID> -pose <n>`
/// jumps straight into a level in a staged state; `-screen <name>` opens a menu page.
enum DebugShot {
    static var level: String? {
        guard let id = UserDefaults.standard.string(forKey: "shot"), Levels.level(id) != nil else { return nil }
        return id
    }
    static var pose: Int { UserDefaults.standard.integer(forKey: "pose") }
    static var screen: String? { UserDefaults.standard.string(forKey: "screen") }
    static var active: Bool { level != nil || screen != nil }
}
