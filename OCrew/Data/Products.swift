import Foundation

enum FixtureKind: String, Codable {
    case shelf, fridge, freezer

    var label: String {
        switch self {
        case .shelf: return "Shelf"
        case .fridge: return "Fridge"
        case .freezer: return "Freezer"
        }
    }
}

/// Physical shape of one unit of product, in meters.
enum ProductShape {
    case box(w: Float, h: Float, d: Float)
    case can(r: Float, h: Float)
    case bottle(r: Float, h: Float)
    case jar(r: Float, h: Float)
    case bag(w: Float, h: Float, d: Float)
    case carton(w: Float, h: Float, d: Float)

    /// Width (along shelf), height, depth (into shelf).
    var size: (w: Float, h: Float, d: Float) {
        switch self {
        case let .box(w, h, d), let .bag(w, h, d): return (w, h, d)
        case let .carton(w, h, d): return (w, h + 0.04, d)
        case let .can(r, h), let .bottle(r, h), let .jar(r, h): return (r * 2, h, r * 2)
        }
    }

    /// Flat products can be stacked on top of each other on a shelf.
    var stackable: Bool {
        switch self {
        case .box, .can, .jar: return size.h < 0.13
        default: return false
        }
    }
}

struct Product: Identifiable {
    let id: String
    let name: String
    let category: String
    let fixture: FixtureKind
    let shape: ProductShape
    let color: UInt32
    let accent: UInt32
    /// Wholesale cost per unit.
    let cost: Double
    /// What shoppers think is a fair shelf price.
    let market: Double
    let perBox: Int

    var boxCost: Double { cost * Double(perBox) }
}

enum Catalog {
    private static func p(_ id: String, _ name: String, _ cat: String, _ fx: FixtureKind, _ shape: ProductShape,
                          _ color: UInt32, _ accent: UInt32, _ cost: Double, _ market: Double, _ perBox: Int) -> Product {
        Product(id: id, name: name, category: cat, fixture: fx, shape: shape, color: color, accent: accent,
                cost: cost, market: market, perBox: perBox)
    }

    static let all: [Product] = [
        // ---------- Grocery: pantry ----------
        p("cereal", "Crunch Flakes Cereal", "Pantry", .shelf, .box(w: 0.19, h: 0.29, d: 0.07), 0xE8B23A, 0xC0392B, 2.10, 3.99, 8),
        p("pasta", "Spaghetti", "Pantry", .shelf, .box(w: 0.14, h: 0.22, d: 0.05), 0x2E86C1, 0xF4D03F, 0.90, 1.79, 12),
        p("soup", "Tomato Soup", "Pantry", .shelf, .can(r: 0.04, h: 0.11), 0xC0392B, 0xECF0F1, 0.70, 1.49, 24),
        p("beans", "Baked Beans", "Pantry", .shelf, .can(r: 0.04, h: 0.11), 0x27AE60, 0xF39C12, 0.60, 1.29, 24),
        p("rice", "Long Grain Rice", "Pantry", .shelf, .bag(w: 0.16, h: 0.24, d: 0.08), 0xF5F5F5, 0x1F618D, 1.60, 2.99, 10),
        p("peanutbutter", "Peanut Butter", "Pantry", .shelf, .jar(r: 0.045, h: 0.13), 0xA0522D, 0xE67E22, 1.80, 3.49, 12),
        p("coffee", "Ground Coffee", "Pantry", .shelf, .can(r: 0.06, h: 0.16), 0x4E342E, 0xD4AC0D, 4.00, 7.49, 8),
        p("oil", "Vegetable Oil", "Pantry", .shelf, .bottle(r: 0.045, h: 0.28), 0xF7DC6F, 0x1E8449, 2.20, 4.29, 10),
        // ---------- Grocery: snacks & drinks ----------
        p("chips", "Potato Chips", "Snacks", .shelf, .bag(w: 0.2, h: 0.3, d: 0.09), 0xF1C40F, 0xE74C3C, 1.20, 2.49, 12),
        p("cookies", "Choc Chip Cookies", "Snacks", .shelf, .box(w: 0.18, h: 0.07, d: 0.12), 0x6E4B3A, 0xF5CBA7, 1.40, 2.79, 12),
        p("water", "Spring Water", "Drinks", .fridge, .bottle(r: 0.035, h: 0.24), 0x5DADE2, 0xFFFFFF, 0.30, 0.99, 24),
        p("soda", "Cola", "Drinks", .fridge, .can(r: 0.033, h: 0.12), 0xE74C3C, 0xFFFFFF, 0.40, 1.19, 24),
        p("energydrink", "Volt Energy", "Drinks", .fridge, .can(r: 0.033, h: 0.16), 0x1ABC9C, 0x17202A, 1.00, 2.49, 24),
        // ---------- Grocery: chilled ----------
        p("milk", "Whole Milk", "Dairy", .fridge, .carton(w: 0.09, h: 0.2, d: 0.09), 0xFDFEFE, 0x3498DB, 1.30, 2.69, 12),
        p("eggs", "Dozen Eggs", "Dairy", .fridge, .box(w: 0.3, h: 0.07, d: 0.11), 0xD5B895, 0xFDFEFE, 1.60, 3.19, 10),
        p("yogurt", "Strawberry Yogurt", "Dairy", .fridge, .jar(r: 0.04, h: 0.08), 0xFADBD8, 0xE91E63, 0.50, 1.09, 20),
        p("cheese", "Cheddar Block", "Dairy", .fridge, .box(w: 0.12, h: 0.04, d: 0.08), 0xF4D03F, 0xE67E22, 2.00, 3.99, 16),
        p("juice", "Orange Juice", "Drinks", .fridge, .carton(w: 0.09, h: 0.24, d: 0.09), 0xF39C12, 0x27AE60, 1.70, 3.29, 10),
        // ---------- Grocery: frozen ----------
        p("pizza", "Frozen Pizza", "Frozen", .freezer, .box(w: 0.3, h: 0.04, d: 0.3), 0xC0392B, 0xF5B041, 2.60, 5.49, 8),
        p("icecream", "Vanilla Ice Cream", "Frozen", .freezer, .can(r: 0.07, h: 0.12), 0xFDEBD0, 0x8E44AD, 2.20, 4.49, 8),
        p("frozenveg", "Frozen Peas", "Frozen", .freezer, .bag(w: 0.18, h: 0.25, d: 0.06), 0x52BE80, 0xFDFEFE, 1.10, 2.29, 12),

        // ---------- Hardware ----------
        p("paint", "Interior Paint", "Paint", .shelf, .can(r: 0.09, h: 0.19), 0xECF0F1, 0x2980B9, 9.00, 17.99, 4),
        p("screws", "Wood Screws", "Fasteners", .shelf, .box(w: 0.12, h: 0.08, d: 0.08), 0x7F8C8D, 0xF1C40F, 2.00, 4.49, 16),
        p("nails", "Box of Nails", "Fasteners", .shelf, .box(w: 0.12, h: 0.08, d: 0.08), 0x34495E, 0xE67E22, 1.80, 3.99, 16),
        p("tape", "Duct Tape", "Supplies", .shelf, .can(r: 0.06, h: 0.05), 0x95A5A6, 0x7F8C8D, 1.50, 3.49, 20),
        p("bulbs", "LED Bulbs", "Electrical", .shelf, .box(w: 0.08, h: 0.14, d: 0.08), 0xF9E79F, 0x1F618D, 2.50, 5.49, 12),
        p("batteries", "AA Batteries", "Electrical", .shelf, .box(w: 0.1, h: 0.16, d: 0.03), 0x17202A, 0xF39C12, 3.50, 7.99, 16),
        p("glue", "Wood Glue", "Supplies", .shelf, .bottle(r: 0.025, h: 0.14), 0xFDFEFE, 0xE74C3C, 1.20, 2.99, 20),
        p("sandpaper", "Sandpaper Pack", "Supplies", .shelf, .box(w: 0.23, h: 0.28, d: 0.02), 0xD4AC0D, 0x6E2C00, 2.00, 4.49, 12),
        p("cord", "Extension Cord", "Electrical", .shelf, .bag(w: 0.18, h: 0.2, d: 0.08), 0xF39C12, 0x17202A, 6.00, 12.99, 6),
        p("toolbox", "Steel Toolbox", "Tools", .shelf, .box(w: 0.4, h: 0.18, d: 0.2), 0xC0392B, 0x17202A, 14.00, 27.99, 3),
        p("workgloves", "Work Gloves", "Tools", .shelf, .bag(w: 0.13, h: 0.25, d: 0.04), 0xF5B041, 0x784212, 3.00, 6.49, 12),
        p("lube", "Lubricant Spray", "Supplies", .shelf, .bottle(r: 0.035, h: 0.2), 0x1F618D, 0xF1C40F, 3.00, 5.99, 12),
        p("hammer", "Claw Hammer", "Tools", .shelf, .box(w: 0.12, h: 0.33, d: 0.05), 0x2C3E50, 0xE67E22, 6.00, 13.99, 6),

        // ---------- Pharmacy ----------
        p("vitamins", "Multivitamins", "Health", .shelf, .jar(r: 0.035, h: 0.1), 0xF39C12, 0xFDFEFE, 4.00, 8.99, 12),
        p("painrelief", "Pain Relief Tablets", "Health", .shelf, .box(w: 0.1, h: 0.12, d: 0.04), 0xE74C3C, 0xFDFEFE, 3.00, 6.49, 16),
        p("bandages", "Bandages", "First Aid", .shelf, .box(w: 0.1, h: 0.14, d: 0.05), 0xFDFEFE, 0x3498DB, 2.00, 4.29, 16),
        p("shampoo", "Shampoo", "Personal Care", .shelf, .bottle(r: 0.04, h: 0.22), 0x8E44AD, 0xFDFEFE, 3.00, 6.99, 12),
        p("toothpaste", "Toothpaste", "Personal Care", .shelf, .box(w: 0.19, h: 0.05, d: 0.04), 0xFDFEFE, 0xC0392B, 1.50, 3.49, 20),
        p("sunscreen", "Sunscreen SPF50", "Personal Care", .shelf, .bottle(r: 0.035, h: 0.17), 0xF7DC6F, 0xE67E22, 4.50, 9.99, 12),
        p("coldmed", "Cold & Flu Relief", "Health", .shelf, .box(w: 0.1, h: 0.14, d: 0.04), 0x2E86C1, 0xF39C12, 4.00, 8.49, 16),
        p("lotion", "Body Lotion", "Personal Care", .shelf, .bottle(r: 0.045, h: 0.2), 0xFDEBD0, 0x48C9B0, 3.50, 7.49, 10),
        p("cotton", "Cotton Balls", "First Aid", .shelf, .bag(w: 0.15, h: 0.18, d: 0.1), 0xFDFEFE, 0x85C1E9, 1.00, 2.49, 12),
        p("deodorant", "Deodorant", "Personal Care", .shelf, .can(r: 0.025, h: 0.15), 0x2C3E50, 0x5DADE2, 2.20, 4.99, 16),

        // ---------- Electronics ----------
        p("charger", "USB-C Charger", "Power", .shelf, .box(w: 0.1, h: 0.15, d: 0.04), 0xFDFEFE, 0x2C3E50, 6.00, 14.99, 12),
        p("cable", "Charging Cable", "Power", .shelf, .box(w: 0.1, h: 0.18, d: 0.03), 0x17202A, 0x3498DB, 3.00, 9.99, 16),
        p("earbuds", "Wireless Earbuds", "Audio", .shelf, .box(w: 0.11, h: 0.11, d: 0.05), 0xFDFEFE, 0x5D6D7E, 15.00, 34.99, 8),
        p("headphones", "Over-Ear Headphones", "Audio", .shelf, .box(w: 0.2, h: 0.25, d: 0.1), 0x1C2833, 0xE74C3C, 22.00, 49.99, 4),
        p("game", "Video Game", "Gaming", .shelf, .box(w: 0.14, h: 0.17, d: 0.02), 0x2C3E50, 0xE74C3C, 25.00, 49.99, 6),
        p("phonecase", "Phone Case", "Accessories", .shelf, .box(w: 0.09, h: 0.18, d: 0.03), 0xEC7063, 0xFDFEFE, 4.00, 14.99, 12),
        p("powerbank", "Power Bank", "Power", .shelf, .box(w: 0.08, h: 0.15, d: 0.03), 0x34495E, 0x1ABC9C, 12.00, 24.99, 8),
        p("sdcard", "Memory Card", "Accessories", .shelf, .box(w: 0.08, h: 0.12, d: 0.015), 0xC0392B, 0x17202A, 5.00, 12.99, 20),
        p("mouse", "Wireless Mouse", "Computer", .shelf, .box(w: 0.12, h: 0.16, d: 0.06), 0x17202A, 0x95A5A6, 8.00, 19.99, 8),
        p("keyboard", "Keyboard", "Computer", .shelf, .box(w: 0.45, h: 0.15, d: 0.04), 0x17202A, 0xECF0F1, 14.00, 29.99, 4),

        // ---------- Pet supply ----------
        p("dogfood", "Dry Dog Food", "Dog", .shelf, .bag(w: 0.3, h: 0.38, d: 0.12), 0xB9770E, 0xC0392B, 8.00, 16.99, 4),
        p("catfood", "Wet Cat Food", "Cat", .shelf, .can(r: 0.04, h: 0.05), 0x2E86C1, 0xF7DC6F, 0.60, 1.49, 24),
        p("treats", "Dog Treats", "Dog", .shelf, .bag(w: 0.15, h: 0.2, d: 0.05), 0xE67E22, 0x6E2C00, 2.50, 5.49, 12),
        p("litter", "Cat Litter", "Cat", .shelf, .box(w: 0.3, h: 0.36, d: 0.15), 0x5D6D7E, 0xF4D03F, 6.00, 12.99, 3),
        p("pettoy", "Chew Toy", "Toys", .shelf, .box(w: 0.12, h: 0.18, d: 0.06), 0x1ABC9C, 0xF1C40F, 2.00, 5.99, 12),
        p("fishfood", "Fish Flakes", "Fish", .shelf, .jar(r: 0.03, h: 0.08), 0x2980B9, 0xF39C12, 1.50, 3.99, 16),
        p("leash", "Dog Leash", "Dog", .shelf, .box(w: 0.1, h: 0.25, d: 0.04), 0xC0392B, 0x17202A, 4.00, 10.99, 10),
        p("birdseed", "Wild Bird Seed", "Birds", .shelf, .bag(w: 0.2, h: 0.3, d: 0.1), 0xF7DC6F, 0x27AE60, 3.00, 6.99, 8),
        p("frozenpet", "Frozen Raw Dinner", "Dog", .freezer, .box(w: 0.2, h: 0.08, d: 0.15), 0xA93226, 0xFDFEFE, 3.00, 6.99, 10),

        // ---------- Garden ----------
        p("seeds", "Seed Packet", "Seeds", .shelf, .box(w: 0.09, h: 0.14, d: 0.012), 0x58D68D, 0xF4D03F, 0.50, 1.99, 30),
        p("soil", "Potting Soil", "Soil", .shelf, .bag(w: 0.35, h: 0.38, d: 0.14), 0x6E2C00, 0x27AE60, 4.00, 8.99, 3),
        p("fertilizer", "Plant Food", "Soil", .shelf, .box(w: 0.18, h: 0.28, d: 0.1), 0x27AE60, 0xF1C40F, 5.00, 11.99, 6),
        p("pot", "Terracotta Pot", "Pots", .shelf, .can(r: 0.08, h: 0.13), 0xBA4A00, 0xA04000, 2.00, 5.49, 10),
        p("gardengloves", "Garden Gloves", "Tools", .shelf, .bag(w: 0.13, h: 0.25, d: 0.04), 0x82E0AA, 0x1E8449, 2.50, 6.49, 12),
        p("hose", "Garden Hose", "Watering", .shelf, .can(r: 0.15, h: 0.12), 0x27AE60, 0x1E8449, 10.00, 22.99, 3),
        p("plantspray", "Plant Mister", "Watering", .shelf, .bottle(r: 0.045, h: 0.25), 0xF4D03F, 0x1E8449, 4.00, 8.99, 10),
        p("trowel", "Hand Trowel", "Tools", .shelf, .box(w: 0.08, h: 0.3, d: 0.05), 0x7F8C8D, 0x229954, 4.00, 9.99, 10),
    ]

    static let byID: [String: Product] = {
        var d: [String: Product] = [:]
        for item in all { d[item.id] = item }
        return d
    }()

    static func product(_ id: String) -> Product? { byID[id] }
}
