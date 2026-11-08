import Foundation

struct SlotSave: Codable {
    var product: String?
    var count: Int
}

struct BoxSave: Codable {
    var product: String
    var count: Int
}

/// A snapshot of a store taken at the start of a day. Quitting mid-day resumes from here.
struct LevelSave: Codable {
    var levelID: String
    var day: Int                 // 1-based
    var cash: Double
    var rating: Double
    var levelProfit: Double
    var prices: [String: Double]
    var slots: [[SlotSave]]      // [fixtureIndex][slotIndex]
    var boxes: [BoxSave]
}

struct ProgressData: Codable {
    var unlocked: [String] = ["grocery"]
    var stars: [String: Int] = [:]
    var bestProfit: [String: Double] = [:]
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
        return dir.appendingPathComponent("progress.json")
    }()

    private init() {
        if let d = try? Data(contentsOf: url), let p = try? JSONDecoder().decode(ProgressData.self, from: d) {
            data = p
        } else {
            data = ProgressData()
        }
    }

    func isUnlocked(_ id: String) -> Bool { data.unlocked.contains(id) }
    func stars(_ id: String) -> Int { data.stars[id] ?? 0 }
    func save(for id: String) -> LevelSave? { data.saves[id] }

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

    func complete(level id: String, stars: Int, profit: Double) {
        data.stars[id] = max(data.stars[id] ?? 0, stars)
        data.bestProfit[id] = max(data.bestProfit[id] ?? 0, profit)
        data.saves[id] = nil
        if let next = Levels.next(after: id), !data.unlocked.contains(next.id) {
            data.unlocked.append(next.id)
        }
        persist()
    }

    func resetAll() {
        data = ProgressData()
        persist()
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(data) {
            try? d.write(to: url, options: .atomic)
        }
    }
}
