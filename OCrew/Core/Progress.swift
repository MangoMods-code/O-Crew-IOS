import Foundation

/// Where one item is when a level is saved mid-way.
struct ItemSave: Codable {
    var product: String
    var expired: Bool
    var loc: Int            // 0 floor, 1 basket, 2 slot
    var f: Int = 0
    var s: Int = 0
    var x: Float = 0
    var z: Float = 0
    var yaw: Float = 0
    var tipped: Bool = false
}

struct LevelSave: Codable {
    var levelID: String
    var elapsed: Double
    var mistakes: Int
    var binned: Int
    var total: Int
    var fixtureCount: Int
    var items: [ItemSave]
}

struct LevelResult {
    let level: OrgLevel
    let time: Double
    let par: Double
    let stars: Int
    let mistakes: Int
    let items: Int
    let bestTime: Double?
    let newBest: Bool
    let next: OrgLevel?
}

struct ProgressData: Codable {
    var unlocked: Int = 1                 // number of levels unlocked, in campaign order
    var stars: [String: Int] = [:]
    var bestTime: [String: Double] = [:]
    var saves: [String: LevelSave] = [:]
    var lastPlayed: String?
    var seenTutorial = false
}

@MainActor
final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()
    @Published private(set) var data: ProgressData

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("progress-v2.json")
    }()

    private init() {
        if let d = try? Data(contentsOf: url), let p = try? JSONDecoder().decode(ProgressData.self, from: d) {
            data = p
        } else {
            data = ProgressData()
        }
    }

    func isUnlocked(_ level: OrgLevel) -> Bool { level.index < data.unlocked }
    func stars(_ id: String) -> Int { data.stars[id] ?? 0 }
    func bestTime(_ id: String) -> Double? { data.bestTime[id] }
    func save(for id: String) -> LevelSave? { data.saves[id] }
    var totalStars: Int { data.stars.values.reduce(0, +) }

    func store(_ save: LevelSave) {
        data.saves[save.levelID] = save
        data.lastPlayed = save.levelID
        persist()
    }

    func clearSave(_ id: String) {
        data.saves[id] = nil
        persist()
    }

    func markTutorialSeen() {
        data.seenTutorial = true
        persist()
    }

    /// Records a finished level. Returns the previous best time.
    @discardableResult
    func complete(_ level: OrgLevel, stars: Int, time: Double) -> Double? {
        let prev = data.bestTime[level.id]
        data.stars[level.id] = max(data.stars[level.id] ?? 0, stars)
        data.bestTime[level.id] = min(prev ?? .greatestFiniteMagnitude, time)
        data.saves[level.id] = nil
        data.unlocked = max(data.unlocked, min(Levels.all.count, level.index + 2))
        data.lastPlayed = level.id
        persist()
        return prev
    }

    func resetAll() {
        data = ProgressData()
        persist()
    }

    private let ioQueue = DispatchQueue(label: "ocrew.progress.io", qos: .utility)

    /// Encodes on the main thread (fast) and writes to disk in the background (never hitches).
    private func persist() {
        guard let d = try? JSONEncoder().encode(data) else { return }
        let target = url
        ioQueue.async { try? d.write(to: target, options: .atomic) }
    }
}
