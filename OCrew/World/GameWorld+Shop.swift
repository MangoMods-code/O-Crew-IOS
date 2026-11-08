import SceneKit
import simd
import UIKit

extension GameWorld {
    // MARK: Boxes

    var padBoxes: [FloorBox] { floorBoxes.filter { $0.onPad }.sorted { $0.id < $1.id } }

    @discardableResult
    func spawnPadBox(product: String, count: Int) -> FloorBox? {
        guard let p = Catalog.product(product) else { return nil }
        let n = padBoxes.count
        guard n < StoreLayout.padCapacity else { return nil }
        let node = Models.cardboardBox(for: p)
        let id = nextBoxID; nextBoxID += 1
        node.name = "fbox:\(id)"
        node.simdPosition = layout.padPosition(n)
        node.simdEulerAngles = SIMD3(0, Float.random(in: -0.06...0.06), 0)
        scene.rootNode.addChildNode(node)
        let box = FloorBox(id: id, product: product, count: count, node: node, onPad: true)
        floorBoxes.append(box)
        return box
    }

    func relayoutPad() {
        for (i, b) in padBoxes.enumerated() {
            let target = layout.padPosition(i)
            if simd_distance(b.node.simdPosition, target) > 0.01 {
                b.node.runAction(.move(to: SCNVector3(target.x, target.y, target.z), duration: 0.25))
            }
        }
    }

    func updateDeliveries() {
        guard !pending.isEmpty else { return }
        var arrived = 0
        pending.removeAll { item in
            guard item.at <= time else { return false }
            if spawnPadBox(product: item.product, count: Catalog.product(item.product)?.perBox ?? 1) != nil {
                arrived += 1
                return true
            }
            return false
        }
        if arrived > 0 {
            deliveryToastPending = true
        }
        if deliveryToastPending && pending.isEmpty {
            deliveryToastPending = false
            Feedback.shared.play(.order)
            toast("Delivery arrived at the loading area", .good)
        }
    }

    func updateCarryVisual() {
        carryNode.childNodes.forEach { $0.removeFromParentNode() }
        guard let c = carried, let p = Catalog.product(c.product) else { return }
        let box = Models.cardboardBox(for: p)
        box.scale = SCNVector3(0.85, 0.85, 0.85)
        Models.setCategory(box, 2)
        carryNode.addChildNode(box)
    }

    // MARK: Ordering & pricing

    /// Returns an error message, or nil on success.
    func placeOrder(_ cart: [String: Int]) -> String? {
        let boxes = cart.values.reduce(0, +)
        guard boxes > 0 else { return "Your cart is empty" }
        if padBoxes.count + pending.count + boxes > StoreLayout.padCapacity {
            return "The loading area only fits \(StoreLayout.padCapacity) boxes. Unpack some first."
        }
        let cost = cart.reduce(0.0) { $0 + (Catalog.product($1.key)?.boxCost ?? 0) * Double($1.value) }
        guard cost <= cash + 0.001 else { return "Not enough cash for this order" }
        cash -= cost
        stats.expenses += cost
        stats.stockSpend += cost
        var i = 0
        for (id, n) in cart.sorted(by: { $0.key < $1.key }) {
            for _ in 0..<n {
                pending.append((at: time + game.delivery.seconds + Double(i) * 0.12, product: id))
                i += 1
            }
        }
        ordersPlaced += 1
        Feedback.shared.play(.cash, volume: 0.6)
        if game.delivery != .instant {
            toast("Order placed — arriving in \(Int(game.delivery.seconds)) seconds", .info)
        }
        updateDeliveries()
        return nil
    }

    func setPrice(_ id: String, _ value: Double) {
        prices[id] = max(0.05, (value * 100).rounded() / 100)
        refreshTags(for: id)
    }

    /// Units of each product on shelves and in boxes.
    func inventory() -> [String: (shelf: Int, boxed: Int)] {
        var out: [String: (shelf: Int, boxed: Int)] = [:]
        for f in fixtures {
            for s in f.slots {
                if let p = s.product, s.count > 0 {
                    out[p, default: (0, 0)].shelf += s.count
                }
            }
        }
        for b in floorBoxes { out[b.product, default: (0, 0)].boxed += b.count }
        if let c = carried { out[c.product, default: (0, 0)].boxed += c.count }
        for p in pending { out[p.product, default: (0, 0)].boxed += Catalog.product(p.product)?.perBox ?? 0 }
        return out
    }

    // MARK: Stocking

    @discardableResult
    func stock(_ slot: Slot, all: Bool = false) -> Bool {
        guard var box = carried, let p = Catalog.product(box.product) else { return false }
        guard box.count > 0 else {
            toast("This box is empty — toss it in the bin", .warn)
            return false
        }
        guard fixtures[slot.fixture].kind == p.fixture else {
            toast("\(p.name) goes in a \(p.fixture.label.lowercased())", .warn)
            Feedback.shared.play(.error, volume: 0.5)
            Feedback.shared.haptic(.warning)
            return false
        }
        if let cur = slot.product, cur != p.id, slot.count > 0 {
            toast("That spot already has \(Catalog.product(cur)?.name ?? "something")", .warn)
            Feedback.shared.play(.error, volume: 0.5)
            return false
        }
        if slot.product != p.id {
            slot.product = p.id
            slot.count = 0
        }
        let cap = slot.capacity
        guard slot.count < cap else {
            toast("That spot is full", .info)
            return false
        }
        let n = all ? min(cap - slot.count, box.count) : 1
        slot.count += n
        box.count -= n
        stockedUnits += n
        carried = box
        slot.rebuild()
        slot.refreshTag(price: prices[p.id], symbol: symbol, visible: display.showPriceTags)
        Feedback.shared.play(.place, volume: 0.7)
        Feedback.shared.haptic(.light)
        if box.count == 0 && game.autoDiscardEmptyBoxes {
            carried = nil
            toast("Box empty — tossed it", .info)
        }
        updateCarryVisual()
        return true
    }

    @discardableResult
    func takeBack(_ slot: Slot) -> Bool {
        guard var box = carried, slot.product == box.product, slot.count > 0,
              let p = Catalog.product(box.product), box.count < p.perBox else { return false }
        slot.count -= 1
        box.count += 1
        carried = box
        slot.rebuild()
        Feedback.shared.play(.pickup, volume: 0.6)
        updateCarryVisual()
        return true
    }

    func dropCarried() {
        guard let box = carried, let p = Catalog.product(box.product) else { return }
        let forward = SIMD2<Float>(-sin(yaw), -cos(yaw))
        var spot = playerPos + forward * 0.7
        let solids = layout.solidRects
        if solids.contains(where: { $0.expanded(0.2).contains(spot) }) { spot = playerPos }
        let node = Models.cardboardBox(for: p)
        let id = nextBoxID; nextBoxID += 1
        node.name = "fbox:\(id)"
        node.simdPosition = SIMD3(spot.x, 0, spot.y)
        node.simdEulerAngles = SIMD3(0, yaw, 0)
        scene.rootNode.addChildNode(node)
        floorBoxes.append(FloorBox(id: id, product: box.product, count: box.count, node: node, onPad: false))
        carried = nil
        updateCarryVisual()
        Feedback.shared.play(.place, volume: 0.5)
    }

    func pickUp(_ id: Int) {
        guard carried == nil else {
            toast("Your hands are full — drop what you're holding first", .warn)
            return
        }
        guard let i = floorBoxes.firstIndex(where: { $0.id == id }) else { return }
        let b = floorBoxes.remove(at: i)
        b.node.removeFromParentNode()
        carried = CarryBox(product: b.product, count: b.count)
        updateCarryVisual()
        Feedback.shared.play(.pickup)
        Feedback.shared.haptic(.light)
        if b.onPad { relayoutPad() }
    }

    // MARK: Interaction

    func interact(_ t: Target?) {
        guard let t = t, !paused else { return }
        switch t {
        case let .slot(f, s):
            guard let slot = fixtures[safe: f]?.slots[safe: s] else { return }
            if carried != nil {
                stock(slot)
            } else if let p = slot.product {
                onOpenPrice?(p)
            } else {
                toast("Empty \(fixtures[f].kind.label.lowercased()) — bring a box to stock it", .info)
            }
        case let .floorBox(id):
            pickUp(id)
        case let .beltItem(i):
            scanItem(i)
        case .terminal:
            chargeCard()
        case .register:
            takeCash()
        case .computer:
            onOpenComputer?()
        case .sign:
            if phase == .prep { openStore() }
            else if phase == .open { beginClosing(early: true) }
        case .bin:
            if let c = carried {
                carried = nil
                updateCarryVisual()
                Feedback.shared.play(.place, volume: 0.5)
                if c.count > 0 { toast("Threw away \(c.count) unsold items", .warn) }
            }
        case let .customer(id):
            guard let c = customers.first(where: { $0.id == id }) else { return }
            interactCustomer(c)
        }
    }

    /// The Drop button: take one item back from a shelf, otherwise drop the box.
    func secondary(_ t: Target?) {
        if let t = t, case let .slot(f, s) = t, let slot = fixtures[safe: f]?.slots[safe: s], takeBack(slot) { return }
        dropCarried()
    }

    func prompt(for t: Target?) -> String? {
        guard let t = t else {
            if let c = carried, let p = Catalog.product(c.product) {
                return "Holding \(p.name) ×\(c.count) — look at a \(p.fixture.label.lowercased()) to stock"
            }
            return nil
        }
        switch t {
        case let .slot(f, s):
            guard let fx = fixtures[safe: f], let slot = fx.slots[safe: s] else { return nil }
            if let c = carried, let p = Catalog.product(c.product) {
                if fx.kind != p.fixture { return "\(p.name) needs a \(p.fixture.label.lowercased())" }
                if let cur = slot.product, cur != p.id, slot.count > 0 { return "Spot has \(Catalog.product(cur)?.name ?? "other stock")" }
                let cap = slot.product == p.id ? slot.capacity : slot.capacity(for: p)
                let have = slot.product == p.id ? slot.count : 0
                if have >= cap { return "Full (\(have)/\(cap))" }
                return "Stock \(p.name)  \(have)/\(cap)  ·  \(c.count) left in box"
            }
            if let id = slot.product, let p = Catalog.product(id) {
                return "\(p.name)  \(slot.count)/\(slot.capacity)  ·  \(formatMoney(prices[id] ?? p.market, symbol: symbol))  ·  Tap to set price"
            }
            return "Empty \(fx.kind.label.lowercased())"
        case let .floorBox(id):
            guard let b = floorBoxes.first(where: { $0.id == id }), let p = Catalog.product(b.product) else { return nil }
            return carried == nil ? "Pick up \(p.name) ×\(b.count)" : "\(p.name) ×\(b.count)  ·  hands full"
        case let .beltItem(i):
            guard let item = belt[safe: i], let p = Catalog.product(item.product) else { return nil }
            return item.scanned ? nil : "Scan \(p.name)"
        case .terminal:
            if let c = checkoutCustomer, c.state == .waitingPayment, !c.paysCash {
                return "Charge card \(formatMoney(beltTotal, symbol: symbol))"
            }
            return "Card reader"
        case .register:
            if let c = checkoutCustomer, c.state == .waitingPayment, c.paysCash {
                return "Take \(formatMoney(c.cashTendered, symbol: symbol)) cash & make change"
            }
            return "Register"
        case .computer:
            return "Computer  ·  Order stock & set prices"
        case .sign:
            switch phase {
            case .prep: return "Flip sign to OPEN the store"
            case .open: return "Close the store early"
            default: return "Closed"
            }
        case .bin:
            return carried != nil ? "Throw away box" : "Trash bin"
        case let .customer(id):
            guard let c = customers.first(where: { $0.id == id }) else { return nil }
            if c.state == .stealing { return "STOP THE SHOPLIFTER!" }
            return c.waved ? nil : "Say hi"
        }
    }

    // MARK: Skills

    var skillMultiplier: Double { game.skillCooldown }

    /// Returns false (and does not start the cooldown) if the skill can't be used right now.
    @discardableResult
    func useSkill(_ s: SkillID, focus: Target?) -> Bool {
        guard !paused else { return false }
        guard skills.isReady(s, now: time) else {
            toast("\(s.name) ready in \(Int(ceil(skills.remaining(s, now: time))))s", .info)
            return false
        }
        switch s {
        case .sprint, .eagleEye:
            break
        case .rushRestock:
            guard carried != nil, let f = focus, case let .slot(fi, si) = f, let slot = fixtures[safe: fi]?.slots[safe: si] else {
                toast("Hold a box and look at a shelf to Rush Restock", .warn)
                Feedback.shared.play(.error, volume: 0.5)
                return false
            }
            guard stock(slot, all: true) else { return false }
        case .expressScan:
            guard belt.contains(where: { !$0.scanned }) else {
                toast("Nothing on the counter to scan", .warn)
                Feedback.shared.play(.error, volume: 0.5)
                return false
            }
            for i in belt.indices where !belt[i].scanned { scanItem(i, quiet: true) }
            Feedback.shared.play(.scan)
        case .crowdCalm:
            guard !customers.isEmpty else {
                toast("No customers to calm", .warn)
                return false
            }
            for c in customers { c.patience = 1 }
            toast("Everyone's feeling patient", .good)
        }
        skills.trigger(s, now: time, multiplier: skillMultiplier)
        Feedback.shared.play(.skill, volume: 0.6)
        Feedback.shared.haptic(.medium)
        return true
    }
}
