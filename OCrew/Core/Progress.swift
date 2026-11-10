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
    /// Bumped whenever store layouts change, so an old save never restores into the wrong shelves.
    static let currentLayout = 2

    var levelID: String
    var elapsed: Double
    var mistakes: Int
    var binned: Int
    var total: Int
    var fixtureCount: Int
    var items: [ItemSave]
    var score: Int?
    var bestStreak: Int?
    var layoutVersion: Int? = LevelSave.currentLayout
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
    let score: Int
    let baseScore: Int
    let timeBonus: Int
    let cleanBonus: Int
    let bestStreak: Int
    let bestScore: Int?
    let newBestScore: Bool
    let next: OrgLevel?
}

struct ProgressData: Codable {
    var unlocked: Int = 1                 // number of levels unlocked, in campaign order
    var stars: [String: Int] = [:]
    var bestTime: [String: Double] = [:]
    var bestScore: [String: Int] = [:]
    var saves: [String: LevelSave] = [:]
    var lastPlayed: String?
    var seenTutorial = false
    // Look
    var glove = 0
    var basket = 0
    // Lifetime stats
    var itemsSorted = 0
    var levelsFinished = 0
    var secondsPlayed: Double = 0
    var bestCombo = 0

    init() {}

    // Decoded field by field so adding new fields never wipes an existing save.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unlocked = try c.decodeIfPresent(Int.self, forKey: .unlocked) ?? 1
        stars = try c.decodeIfPresent([String: Int].self, forKey: .stars) ?? [:]
        bestTime = try c.decodeIfPresent([String: Double].self, forKey: .bestTime) ?? [:]
        bestScore = try c.decodeIfPresent([String: Int].self, forKey: .bestScore) ?? [:]
        saves = (try? c.decodeIfPresent([String: LevelSave].self, forKey: .saves)) ?? [:]
        lastPlayed = try c.decodeIfPresent(String.self, forKey: .lastPlayed)
        seenTutorial = try c.decodeIfPresent(Bool.self, forKey: .seenTutorial) ?? false
        glove = try c.decodeIfPresent(Int.self, forKey: .glove) ?? 0
        basket = try c.decodeIfPresent(Int.self, forKey: .basket) ?? 0
        itemsSorted = try c.decodeIfPresent(Int.self, forKey: .itemsSorted) ?? 0
        levelsFinished = try c.decodeIfPresent(Int.self, forKey: .levelsFinished) ?? 0
        secondsPlayed = try c.decodeIfPresent(Double.self, forKey: .secondsPlayed) ?? 0
        bestCombo = try c.decodeIfPresent(Int.self, forKey: .bestCombo) ?? 0
    }
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
    func bestScore(_ id: String) -> Int? { data.bestScore[id] }
    var totalStars: Int { data.stars.values.reduce(0, +) }

    /// A saved, unfinished run of this level (only if it matches the current store layouts).
    func save(for id: String) -> LevelSave? {
        guard let s = data.saves[id], s.layoutVersion == LevelSave.currentLayout else { return nil }
        return s
    }

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

    func addPlayTime(_ seconds: Double) {
        guard seconds > 0 else { return }
        data.secondsPlayed += seconds
        persist()
    }

    func setLook(glove: Int? = nil, basket: Int? = nil) {
        if let g = glove { data.glove = g }
        if let b = basket { data.basket = b }
        persist()
    }

    /// Records a finished level. Returns the previous bests.
    @discardableResult
    func complete(_ level: OrgLevel, stars: Int, time: Double, score: Int, items: Int, streak: Int) -> (time: Double?, score: Int?) {
        let prev = (data.bestTime[level.id], data.bestScore[level.id])
        data.stars[level.id] = max(data.stars[level.id] ?? 0, stars)
        data.bestTime[level.id] = min(prev.0 ?? .greatestFiniteMagnitude, time)
        data.bestScore[level.id] = max(prev.1 ?? 0, score)
        data.saves[level.id] = nil
        data.unlocked = max(data.unlocked, min(Levels.all.count, level.index + 2))
        data.lastPlayed = level.id
        data.itemsSorted += items
        data.levelsFinished += 1
        data.bestCombo = max(data.bestCombo, streak)
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
