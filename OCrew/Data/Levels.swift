import Foundation

struct StoreLevel: Identifiable {
    let id: String
    let number: Int
    let name: String
    let blurb: String
    /// Interior size in meters (x = width, z = depth). Depth includes the 7 m front area.
    let width: Float
    let depth: Float
    let leftWall: [FixtureKind]?
    let rightWall: [FixtureKind]?
    let backWall: [FixtureKind]?
    let maxGondolaColumns: Int
    let products: [String]
    let days: Int
    let profitGoal: Double
    let ratingGoal: Double
    let startingCash: Double
    let dailyRent: Double
    let customersPerDay: Double
    let maxCustomers: Int
    let floor: UInt32
    let floorAlt: UInt32
    let wall: UInt32
    let trim: UInt32
    let shelfColor: UInt32
}

enum Levels {
    static let all: [StoreLevel] = [
        StoreLevel(
            id: "grocery", number: 1, name: "Corner Grocery",
            blurb: "A tiny neighborhood grocer. Learn the ropes: order, stock, price, ring people up.",
            width: 12, depth: 16, leftWall: [.fridge, .freezer], rightWall: [.shelf], backWall: [.shelf, .shelf, .fridge],
            maxGondolaColumns: 2,
            products: ["cereal", "pasta", "soup", "beans", "rice", "chips", "cookies", "water", "soda",
                       "milk", "eggs", "yogurt", "juice", "pizza", "icecream", "peanutbutter"],
            days: 5, profitGoal: 450, ratingGoal: 3.0, startingCash: 400, dailyRent: 40,
            customersPerDay: 30, maxCustomers: 8,
            floor: 0xE9E4D8, floorAlt: 0xD8D1C2, wall: 0xF3EBDD, trim: 0x2E7D4F, shelfColor: 0xDADDE1),
        StoreLevel(
            id: "hardware", number: 2, name: "Hardware Depot",
            blurb: "Bulky, pricey stock and handy customers who know what things should cost.",
            width: 14, depth: 17, leftWall: [.shelf], rightWall: [.shelf], backWall: [.shelf],
            maxGondolaColumns: 3,
            products: ["paint", "screws", "nails", "tape", "bulbs", "batteries", "glue", "sandpaper",
                       "cord", "toolbox", "workgloves", "lube", "hammer"],
            days: 6, profitGoal: 1100, ratingGoal: 3.2, startingCash: 700, dailyRent: 90,
            customersPerDay: 28, maxCustomers: 9,
            floor: 0xBFC5CA, floorAlt: 0xAEB5BB, wall: 0xE5E2DA, trim: 0xD35400, shelfColor: 0xE67E22),
        StoreLevel(
            id: "pharmacy", number: 3, name: "Neighborhood Pharmacy",
            blurb: "Small items, lots of them, and impatient people who just want their cold medicine.",
            width: 13, depth: 17, leftWall: [.fridge], rightWall: [.shelf], backWall: [.shelf],
            maxGondolaColumns: 3,
            products: ["vitamins", "painrelief", "bandages", "shampoo", "toothpaste", "sunscreen", "coldmed",
                       "lotion", "cotton", "deodorant", "water", "soda", "energydrink", "juice"],
            days: 6, profitGoal: 1300, ratingGoal: 3.4, startingCash: 700, dailyRent: 100,
            customersPerDay: 34, maxCustomers: 10,
            floor: 0xF4F6F7, floorAlt: 0xE5E8E8, wall: 0xFBFCFC, trim: 0x2471A3, shelfColor: 0xF8F9F9),
        StoreLevel(
            id: "electronics", number: 4, name: "Electronics Outlet",
            blurb: "High-value gadgets. Fewer customers, bigger baskets, and shoplifters love it here.",
            width: 14, depth: 17, leftWall: [.fridge], rightWall: [.shelf], backWall: [.shelf],
            maxGondolaColumns: 3,
            products: ["charger", "cable", "earbuds", "headphones", "game", "phonecase", "powerbank", "sdcard",
                       "mouse", "keyboard", "batteries", "energydrink", "soda"],
            days: 7, profitGoal: 3200, ratingGoal: 3.5, startingCash: 1200, dailyRent: 180,
            customersPerDay: 24, maxCustomers: 9,
            floor: 0x2C3E50, floorAlt: 0x273746, wall: 0xD6DBDF, trim: 0x8E44AD, shelfColor: 0x1C2833),
        StoreLevel(
            id: "pets", number: 5, name: "Pet Supply Co.",
            blurb: "Heavy bags, tiny cans, and very loyal regulars. Don't run out of cat food.",
            width: 14, depth: 18, leftWall: [.freezer, .shelf], rightWall: [.shelf], backWall: [.shelf],
            maxGondolaColumns: 3,
            products: ["dogfood", "catfood", "treats", "litter", "pettoy", "fishfood", "leash", "birdseed", "frozenpet"],
            days: 7, profitGoal: 2000, ratingGoal: 3.6, startingCash: 900, dailyRent: 140,
            customersPerDay: 32, maxCustomers: 10,
            floor: 0xEDE0C8, floorAlt: 0xE0D0B3, wall: 0xFFF8EC, trim: 0x16A085, shelfColor: 0xF0F3F4),
        StoreLevel(
            id: "garden", number: 6, name: "Garden Center",
            blurb: "Seasonal rush. Huge soil bags, tiny seed packets, and a lot of floor to cover.",
            width: 16, depth: 18, leftWall: [.shelf], rightWall: [.shelf], backWall: [.shelf],
            maxGondolaColumns: 4,
            products: ["seeds", "soil", "fertilizer", "pot", "gardengloves", "hose", "plantspray", "trowel", "birdseed"],
            days: 7, profitGoal: 2400, ratingGoal: 3.6, startingCash: 1000, dailyRent: 160,
            customersPerDay: 36, maxCustomers: 11,
            floor: 0xB9A88E, floorAlt: 0xAA987D, wall: 0xF2EEE3, trim: 0x1E8449, shelfColor: 0x7E5109),
        StoreLevel(
            id: "supermarket", number: 7, name: "City Supermarket",
            blurb: "The big one. Everything, everywhere, all at once. Keep it stocked and keep the line moving.",
            width: 20, depth: 22, leftWall: [.fridge, .fridge, .freezer], rightWall: [.shelf], backWall: [.shelf, .fridge],
            maxGondolaColumns: 5,
            products: ["cereal", "pasta", "soup", "beans", "rice", "chips", "cookies", "water", "soda", "energydrink",
                       "milk", "eggs", "yogurt", "cheese", "juice", "pizza", "icecream", "frozenveg", "peanutbutter",
                       "coffee", "oil", "shampoo", "toothpaste", "painrelief", "deodorant", "catfood", "dogfood",
                       "batteries", "bulbs"],
            days: 8, profitGoal: 2000, ratingGoal: 3.8, startingCash: 1800, dailyRent: 200,
            customersPerDay: 48, maxCustomers: 14,
            floor: 0xECEFF1, floorAlt: 0xDDE2E5, wall: 0xFAFAFA, trim: 0xC0392B, shelfColor: 0xE5E8E8),
    ]

    static func level(_ id: String) -> StoreLevel? { all.first { $0.id == id } }

    static func next(after id: String) -> StoreLevel? {
        guard let l = level(id) else { return nil }
        return all.first { $0.number == l.number + 1 }
    }
}
