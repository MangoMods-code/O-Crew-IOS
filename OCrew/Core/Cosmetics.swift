import Foundation

/// A glove or basket color, unlocked by earning stars.
struct Cosmetic: Identifiable {
    let id: Int
    let name: String
    let color: UInt32
    let stars: Int
}

enum Cosmetics {
    static let gloves: [Cosmetic] = [
        Cosmetic(id: 0, name: "Charcoal", color: 0x2E3B48, stars: 0),
        Cosmetic(id: 1, name: "Safety Orange", color: 0xE8731A, stars: 3),
        Cosmetic(id: 2, name: "Royal Blue", color: 0x2456B4, stars: 6),
        Cosmetic(id: 3, name: "Forest", color: 0x1E7A46, stars: 10),
        Cosmetic(id: 4, name: "Crimson", color: 0xB3202C, stars: 15),
        Cosmetic(id: 5, name: "Violet", color: 0x6C3FB5, stars: 21),
        Cosmetic(id: 6, name: "Hi-Vis", color: 0xC9D61C, stars: 30),
        Cosmetic(id: 7, name: "Snow", color: 0xE9EEF2, stars: 42),
        Cosmetic(id: 8, name: "Gold", color: 0xD4A017, stars: 57),
    ]

    static let baskets: [Cosmetic] = [
        Cosmetic(id: 0, name: "Classic Red", color: 0xD62828, stars: 0),
        Cosmetic(id: 1, name: "Ocean", color: 0x1F6FD0, stars: 2),
        Cosmetic(id: 2, name: "Lime", color: 0x3FA63A, stars: 5),
        Cosmetic(id: 3, name: "Sunny", color: 0xF0B429, stars: 9),
        Cosmetic(id: 4, name: "Grape", color: 0x7E3FC4, stars: 14),
        Cosmetic(id: 5, name: "Midnight", color: 0x2A2F38, stars: 20),
        Cosmetic(id: 6, name: "Bubblegum", color: 0xE64C8B, stars: 28),
        Cosmetic(id: 7, name: "Teal", color: 0x12A5A0, stars: 38),
        Cosmetic(id: 8, name: "Gold", color: 0xC99A1A, stars: 54),
    ]

    static func glove(_ id: Int) -> Cosmetic { gloves.first { $0.id == id } ?? gloves[0] }
    static func basket(_ id: Int) -> Cosmetic { baskets.first { $0.id == id } ?? baskets[0] }
}
