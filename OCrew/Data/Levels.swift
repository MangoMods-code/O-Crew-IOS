import Foundation

/// A store type. Each store has three stages that get messier.
struct StoreTheme {
    let id: String
    let name: String
    let blurb: String
    let products: [String]
    let floor: UInt32
    let floorAlt: UInt32
    let wall: UInt32
    let trim: UInt32
    let shelfColor: UInt32
}

/// One playable level: a store + stage.
struct OrgLevel: Identifiable {
    let theme: StoreTheme
    let stage: Int            // 1...3
    let index: Int            // 0-based position in the campaign
    let products: [String]
    let slotsPerProduct: Int
    let fill: Double          // fraction of each planned spot that gets items
    let misplaced: Double     // fraction of products that start on the wrong shelf
    let expired: Int          // expired items mixed into the mess

    var id: String { "\(theme.id)-\(stage)" }
    var number: Int { index + 1 }
    var title: String { theme.name }
    var stageName: String {
        switch stage {
        case 1: return "Morning Mess"
        case 2: return "Wrong Aisles"
        default: return "Total Chaos"
        }
    }
    var twists: [String] {
        var t: [String] = []
        if misplaced > 0 { t.append("Items on the wrong shelves") }
        if expired > 0 { t.append("\(expired) expired items for the trash") }
        return t
    }
}

enum Levels {
    static let themes: [StoreTheme] = [
        StoreTheme(id: "grocery", name: "Corner Grocery",
                   blurb: "A tiny neighborhood grocer after a rough night. Pantry, snacks, dairy and frozen.",
                   products: ["cereal", "bread", "soup", "chips", "water", "milk", "pizza", "ketchup", "pasta", "cookies", "soda", "eggs", "icecream", "flour", "beans", "crackers", "juice", "yogurt", "candy", "mustard", "butter", "fries", "rice", "sugar", "peanutbutter", "bagels", "tea", "granola", "mayo", "sausages", "waffles", "oatmeal", "hotsauce", "bakingsoda", "bacon", "nuggets"],
                   floor: 0xE9E4D8, floorAlt: 0xD8D1C2, wall: 0xF3EBDD, trim: 0x2E7D4F, shelfColor: 0xDADDE1),
        StoreTheme(id: "hardware", name: "Hardware Depot",
                   blurb: "Screws, paint and power tools everywhere. Sort it by department.",
                   products: ["paint", "screws", "bulbs", "hammer", "tape", "wrench", "padlock", "drill", "nails", "batteries", "spraypaint", "sealant", "flashlight", "screwdriver", "zipties", "cord", "brush", "glue", "tapemeasure", "chain", "hinges", "saw", "sandpaper", "roller", "toolbox", "workgloves", "lube"],
                   floor: 0xBFC5CA, floorAlt: 0xAEB5BB, wall: 0xE5E2DA, trim: 0xD35400, shelfColor: 0xE67E22),
        StoreTheme(id: "pharmacy", name: "Neighborhood Pharmacy",
                   blurb: "Small boxes, lots of them, and they all look alike. Read the signs carefully.",
                   products: ["vitamins", "toothpaste", "bandages", "shampoo", "water", "painrelief", "mouthwash", "cotton", "handsoap", "icepack", "coldmed", "floss", "gauze", "sunscreen", "energydrink", "allergy", "toothbrush", "lotion", "deodorant", "coughsyrup", "thermometer", "razors", "juice", "insulin"],
                   floor: 0xF4F6F7, floorAlt: 0xE5E8E8, wall: 0xFBFCFC, trim: 0x2471A3, shelfColor: 0xF8F9F9),
        StoreTheme(id: "electronics", name: "Electronics Outlet",
                   blurb: "Cables, cases, chargers. Somebody dropped every box in the building.",
                   products: ["charger", "cable", "earbuds", "game", "phonecase", "hdmi", "mouse", "energydrink", "speaker", "controller", "powerbank", "sdcard", "webcam", "adapter", "keyboard", "headphones", "usbdrive", "smartwatch", "batteries", "headset", "usbcable", "fitband", "soda"],
                   floor: 0x2C3E50, floorAlt: 0x273746, wall: 0xD6DBDF, trim: 0x8E44AD, shelfColor: 0x1C2833),
        StoreTheme(id: "pets", name: "Pet Supply Co.",
                   blurb: "The dogs got loose in the stockroom. Heavy bags, tiny cans.",
                   products: ["dogfood", "catfood", "treats", "pettoy", "fishfood", "frozenpet", "litter", "leash", "catnip", "dogshampoo", "hamsterfood", "petbowl", "birdseed", "cattoy", "petbrush", "aquafilter", "bedding"],
                   floor: 0xEDE0C8, floorAlt: 0xE0D0B3, wall: 0xFFF8EC, trim: 0x16A085, shelfColor: 0xF0F3F4),
        StoreTheme(id: "garden", name: "Garden Center",
                   blurb: "Spring rush aftermath. Seeds, soil, pots and tools in one big pile.",
                   products: ["seeds", "soil", "pot", "trowel", "fertilizer", "wateringcan", "bugspray", "gardengloves", "shears", "flowerbulbs", "hose", "mulch", "plantspray", "sprinkler", "rake", "grassseed", "plantlabels", "seedtray", "slugpellets", "birdseed"],
                   floor: 0xB9A88E, floorAlt: 0xAA987D, wall: 0xF2EEE3, trim: 0x1E8449, shelfColor: 0x7E5109),
        StoreTheme(id: "supermarket", name: "City Supermarket",
                   blurb: "The big one. Every department, every aisle, every item on the floor.",
                   products: ["cereal", "bread", "soup", "chips", "water", "milk", "pizza", "shampoo", "catfood", "ketchup", "pasta", "cookies", "soda", "eggs", "icecream", "toothpaste", "dogfood", "batteries", "flour", "beans", "crackers", "juice", "yogurt", "candy", "painrelief", "mustard", "butter", "fries", "rice", "sugar", "bulbs", "peanutbutter", "coffee", "oil", "bagels", "tea", "granola", "mayo", "sausages", "waffles", "energydrink", "cheese", "frozenveg", "deodorant", "handsoap", "treats", "oatmeal", "bacon", "nuggets", "mouthwash"],
                   floor: 0xECEFF1, floorAlt: 0xDDE2E5, wall: 0xFAFAFA, trim: 0xC0392B, shelfColor: 0xE5E8E8),
    ]

    static let all: [OrgLevel] = {
        var out: [OrgLevel] = []
        for theme in themes {
            let n = theme.products.count
            for stage in 1...3 {
                let count: Int
                switch stage {
                case 1: count = max(6, Int((Double(n) * 0.5).rounded(.up)))
                case 2: count = max(8, Int((Double(n) * 0.75).rounded(.up)))
                default: count = n
                }
                let big = n > 30
                out.append(OrgLevel(
                    theme: theme, stage: stage, index: out.count,
                    products: Array(theme.products.prefix(count)),
                    slotsPerProduct: stage == 3 && !big ? 2 : 1,
                    fill: stage == 1 ? 0.7 : stage == 2 ? 0.75 : 0.7,
                    misplaced: stage == 1 ? 0 : stage == 2 ? 0.25 : 0.3,
                    expired: stage == 3 ? 6 + n / 2 : 0))
            }
        }
        return out
    }()

    static func level(_ id: String) -> OrgLevel? { all.first { $0.id == id } }

    static func next(after id: String) -> OrgLevel? {
        guard let l = level(id), l.index + 1 < all.count else { return nil }
        return all[l.index + 1]
    }
}
