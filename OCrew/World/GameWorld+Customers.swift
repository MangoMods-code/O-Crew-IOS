import SceneKit
import simd
import UIKit

extension GameWorld {
    // MARK: Spawning

    func trySpawn(dt: Double, minutes: Double) {
        guard customers.count < level.maxCustomers else { return }
        let rush = (minutes >= 720 && minutes < 780) || (minutes >= 1020 && minutes < 1110) ? 1.8 : 1.0
        let mood = 0.55 + 0.45 * (rating / 3.5)
        let perDay = level.customersPerDay * game.customerRate * mood
        let perSecond = perDay / max(60, game.dayLengthMinutes * 60) * rush / 1.15
        if Double.random(in: 0...1) < perSecond * dt { spawnCustomer() }
    }

    func spawnCustomer() {
        let c = Customer(id: nextCustomerID, at: layout.spawnPoint)
        nextCustomerID += 1
        // Shopping list
        let avgPrice = level.products.compactMap { Catalog.product($0)?.market }.reduce(0, +) / Double(max(1, level.products.count))
        let entries = avgPrice > 12 ? Int.random(in: 1...3) : Int.random(in: 2...5)
        var picks = level.products.shuffled()
        for _ in 0..<min(entries, picks.count) {
            let id = picks.removeFirst()
            let market = Catalog.product(id)?.market ?? 1
            let roll = Double.random(in: 0...1)
            let qty = market > 12 ? 1 : (roll < 0.6 ? 1 : roll < 0.9 ? 2 : 3)
            c.list.append((product: id, qty: qty))
        }
        let theftBase = level.id == "electronics" ? 0.09 : 0.05
        c.isThief = Double.random(in: 0...1) < theftBase * game.theftRate
        c.paysCash = Double.random(in: 0...1) < game.cashCustomerShare
        scene.rootNode.addChildNode(c.node)
        customers.append(c)
        Feedback.shared.play(.chime, volume: 0.35)
        planNext(c)
    }

    // MARK: AI

    func planNext(_ c: Customer, retry: Bool = false) {
        while c.listIndex < c.list.count {
            let want = c.list[c.listIndex]
            var best: Slot?
            var bestD = Float.greatestFiniteMagnitude
            var exists = false
            for f in fixtures {
                for s in f.slots where s.product == want.product {
                    exists = true
                    guard s.count > 0 else { continue }
                    let d = simd_distance(s.standPoint, c.pos)
                    if d < bestD { bestD = d; best = s }
                }
            }
            if let s = best {
                c.targetSlot = (s.fixture, s.index)
                c.path = nav.path(from: c.pos, to: s.standPoint)
                c.state = .toShelf
                return
            }
            // Nothing on the shelves
            let name = Catalog.product(want.product)?.name ?? want.product
            if exists {
                c.penalties += game.outOfStockPenalty ? 0.8 : 0.3
                c.patience -= 0.08
                stats.outOfStock += 1
                showThought(c, "Out of \(name)?")
            } else {
                c.penalties += game.outOfStockPenalty ? 0.4 : 0.15
                showThought(c, "No \(name)?")
            }
            stats.missing[want.product, default: 0] += 1
            c.missing.append(want.product)
            c.listIndex += 1
        }
        finishShopping(c)
    }

    private func showThought(_ c: Customer, _ text: String) {
        guard display.showToasts else { return }
        popup(text, at: SIMD3(c.pos.x, 2.25, c.pos.y), color: StatusPalette.bad(display.colorblind))
    }

    func finishShopping(_ c: Customer) {
        c.targetSlot = nil
        if c.basket.isEmpty {
            leave(c, angry: false)
        } else if c.isThief {
            c.state = .stealing
            c.path = nav.path(from: c.pos, to: layout.doorInside) + [layout.exitPoint]
        } else {
            joinQueue(c)
        }
    }

    func joinQueue(_ c: Customer) {
        queue.append(c)
        c.queueIndex = queue.count - 1
        c.state = .toQueue
        c.path = nav.path(from: c.pos, to: layout.queueSpot(c.queueIndex))
    }

    func reindexQueue() {
        for (i, c) in queue.enumerated() where c.queueIndex != i {
            c.queueIndex = i
            if c.state == .queued || c.state == .toQueue {
                c.state = .toQueue
                c.path = nav.path(from: c.pos, to: layout.queueSpot(i))
            }
        }
    }

    func leave(_ c: Customer, angry: Bool) {
        if let i = queue.firstIndex(where: { $0 === c }) {
            queue.remove(at: i)
            reindexQueue()
        }
        if checkoutCustomer === c { clearBelt(); checkoutCustomer = nil }
        if angry {
            stats.angry += 1
            rating += (0.5 - rating) * 0.12
            c.penalties = 99
            if display.showToasts {
                popup("😠", at: SIMD3(c.pos.x, 2.3, c.pos.y), color: StatusPalette.bad(display.colorblind))
            }
        }
        c.showBasket(false)
        c.state = .leaving
        c.path = nav.path(from: c.pos, to: layout.doorInside) + [layout.exitPoint]
    }

    func despawn(_ c: Customer) {
        c.node.removeFromParentNode()
        customers.removeAll { $0 === c }
    }

    func updateCustomers(dt: Float) {
        let patienceMul = max(0.2, game.customerPatience)
        let eagle = skills.isActive(.eagleEye, now: time)
        let showBars = display.showPatienceBars
        for c in customers {
            switch c.state {
            case .entering, .toShelf:
                c.patience -= Double(dt) / (320 * patienceMul)
                if c.follow(dt: dt) { arriveAtShelf(c) }
            case .picking:
                c.timer -= Double(dt)
                c.animate(moving: false, dt: dt)
                if c.timer <= 0 { takeFromShelf(c) }
            case .toQueue:
                c.patience -= Double(dt) / (110 * patienceMul)
                if c.follow(dt: dt) {
                    c.state = .queued
                    c.face(c.queueIndex == 0 ? layout.payPoint + SIMD2(-1, 0) : layout.queueSpot(max(0, c.queueIndex - 1)))
                }
            case .queued:
                c.patience -= Double(dt) / (85 * patienceMul)
                c.animate(moving: false, dt: dt)
                if c.queueIndex == 0 && checkoutCustomer == nil { startCheckout(c) }
            case .atCounter, .waitingPayment:
                c.patience -= Double(dt) / (95 * patienceMul)
                c.animate(moving: false, dt: dt)
            case .leaving:
                if c.follow(dt: dt) { finishVisit(c) }
            case .stealing:
                if c.follow(dt: dt, speedMul: 1.3) { thiefEscaped(c) }
            }
            if c.patience <= 0 {
                switch c.state {
                case .entering, .toShelf, .picking, .toQueue, .queued, .atCounter, .waitingPayment:
                    c.patience = 0
                    leave(c, angry: true)
                default: break
                }
            }
            let barVisible = showBars && c.state != .leaving && c.state != .stealing && c.state != .entering
            c.setPatienceBar(visible: barVisible, colorblind: display.colorblind)
            c.setHighlighted(eagle && c.isThief && c.state != .leaving, time: time)
        }
    }

    private func arriveAtShelf(_ c: Customer) {
        guard let ts = c.targetSlot, let slot = fixtures[safe: ts.fixture]?.slots[safe: ts.slot] else { planNext(c); return }
        let want = c.list[c.listIndex]
        guard slot.product == want.product, slot.count > 0 else {
            // Someone else emptied it — try somewhere else.
            planNext(c)
            return
        }
        c.face(SIMD2(slot.worldCenter.x, slot.worldCenter.z))
        // Price check
        let p = Catalog.product(want.product)!
        let price = prices[want.product] ?? p.market
        let ratio = price / p.market
        let tolerance = 0.22 / max(0.2, game.priceSensitivity)
        var accept = true
        if ratio > 1 + tolerance {
            accept = Double.random(in: 0...1) < 0.12
        } else if ratio > 1 {
            accept = Double.random(in: 0...1) < 1 - (ratio - 1) / tolerance * 0.45
        } else {
            c.bonus += min(0.4, (1 - ratio) * 0.8)
        }
        if !accept {
            c.penalties += 0.45
            stats.tooExpensive += 1
            if display.showToasts {
                popup("Too pricey!", at: SIMD3(c.pos.x, 2.25, c.pos.y), color: StatusPalette.warn(display.colorblind))
            }
            c.listIndex += 1
            planNext(c)
            return
        }
        c.state = .picking
        c.timer = 0.5 + Double(want.qty) * 0.35
    }

    private func takeFromShelf(_ c: Customer) {
        guard let ts = c.targetSlot, let slot = fixtures[safe: ts.fixture]?.slots[safe: ts.slot] else { planNext(c); return }
        let want = c.list[c.listIndex]
        guard slot.product == want.product, slot.count > 0 else { planNext(c); return }
        let n = min(want.qty, slot.count)
        slot.count -= n
        slot.rebuild()
        for _ in 0..<n { c.basket.append(want.product) }
        if n < want.qty { c.penalties += 0.25 }
        c.showBasket(true)
        c.listIndex += 1
        planNext(c)
    }

    private func finishVisit(_ c: Customer) {
        if c.penalties < 50 {
            let score = max(0, min(5, 5 - c.penalties + c.bonus))
            rating += (score - rating) * 0.1
        }
        rating = max(0, min(5, rating))
        despawn(c)
    }

    private func thiefEscaped(_ c: Customer) {
        let value = c.basket.reduce(0.0) { $0 + (prices[$1] ?? 0) }
        stats.thefts += 1
        stats.stolenValue += value
        toast("A shoplifter got away with \(formatMoney(value, symbol: symbol))", .bad)
        Feedback.shared.play(.alarm, volume: 0.6)
        despawn(c)
    }

    func interactCustomer(_ c: Customer) {
        if c.state == .stealing {
            let value = c.basket.reduce(0.0) { $0 + (prices[$1] ?? 0) }
            stats.caught += 1
            cash += value
            stats.revenue += value
            c.basket.removeAll()
            c.isThief = false
            c.setHighlighted(false, time: time)
            c.showBasket(false)
            c.state = .leaving
            c.penalties = 99
            c.path = nav.path(from: c.pos, to: layout.doorInside) + [layout.exitPoint]
            rating = min(5, rating + 0.05)
            toast("Caught a shoplifter! Recovered \(formatMoney(value, symbol: symbol))", .good)
            popup("CAUGHT!", at: SIMD3(c.pos.x, 2.3, c.pos.y), color: StatusPalette.good(display.colorblind))
            Feedback.shared.play(.alarm)
            Feedback.shared.haptic(.success)
            return
        }
        if !c.waved {
            c.waved = true
            c.bonus += 0.3
            c.patience = min(1, c.patience + 0.1)
            popup("👋", at: SIMD3(c.pos.x, 2.3, c.pos.y), color: 0x2E86C1)
        }
    }

    // MARK: Checkout

    private func beltPosition(_ i: Int) -> SIMD3<Float> {
        let c = layout.counter
        let col = i % 3, row = i / 3
        return SIMD3(c.center.x - 0.17 + Float(col) * 0.17, 0.975, c.minZ + 0.3 + Float(row) * 0.19)
    }

    private var bagPosition: SIMD3<Float> {
        let c = layout.counter
        return SIMD3(c.center.x, 0.975, c.maxZ - 0.35)
    }

    func startCheckout(_ c: Customer) {
        checkoutCustomer = c
        c.state = .atCounter
        c.face(c.pos + SIMD2(-1, 0))
        c.showBasket(false)
        clearBelt()
        beltTotal = 0
        for (i, id) in c.basket.enumerated() {
            guard let p = Catalog.product(id) else { continue }
            let n = Models.productNode(p)
            n.name = "belt:\(i)"
            let pos = beltPosition(min(i, 17))
            n.simdPosition = pos + SIMD3(0, Float(i / 18) * 0.12, 0)
            n.simdEulerAngles = SIMD3(0, Float.random(in: -0.4...0.4) + .pi / 2, 0)
            n.opacity = 0
            n.runAction(.sequence([.wait(duration: Double(i) * 0.08), .fadeIn(duration: 0.15)]))
            // Make small items easier to tap with an invisible hit box
            let hit = SCNNode(geometry: SCNBox(width: 0.16, height: 0.16, length: 0.16, chamferRadius: 0))
            hit.geometry?.firstMaterial = Models.invisible()
            hit.position.y = 0.08
            n.addChildNode(hit)
            scene.rootNode.addChildNode(n)
            belt.append(BeltItem(node: n, product: id, scanned: false))
        }
    }

    func clearBelt() {
        for b in belt { b.node.removeFromParentNode() }
        belt.removeAll()
        beltTotal = 0
    }

    func scanItem(_ i: Int, quiet: Bool = false) {
        guard i < belt.count, !belt[i].scanned, let c = checkoutCustomer, c.state == .atCounter else { return }
        belt[i].scanned = true
        let id = belt[i].product
        beltTotal += prices[id] ?? Catalog.product(id)?.market ?? 0
        let node = belt[i].node
        node.name = nil
        let dest = bagPosition + SIMD3(Float.random(in: -0.1...0.1), 0, Float.random(in: -0.08...0.08))
        node.runAction(.sequence([.move(to: SCNVector3(dest.x, dest.y, dest.z), duration: 0.18), .wait(duration: 0.3),
                                  .fadeOut(duration: 0.2), .removeFromParentNode()]))
        if !quiet {
            Feedback.shared.play(.scan)
            Feedback.shared.haptic(.light)
        }
        if belt.allSatisfy({ $0.scanned }) {
            c.state = .waitingPayment
            if c.paysCash {
                c.cashTendered = tenderAmount(for: beltTotal)
                toast("Total \(formatMoney(beltTotal, symbol: symbol)) — paying \(formatMoney(c.cashTendered, symbol: symbol)) cash. Tap the register.", .info)
            } else {
                toast("Total \(formatMoney(beltTotal, symbol: symbol)) — paying by card. Tap the card reader.", .info)
            }
        }
    }

    private func tenderAmount(for total: Double) -> Double {
        let options: [Double] = [ceil(total), ceil(total / 5) * 5, ceil(total / 10) * 10, ceil(total / 20) * 20,
                                 total < 50 ? 50 : ceil(total / 50) * 50, total < 100 ? 100 : ceil(total / 100) * 100]
        let valid = options.filter { $0 >= total - 0.001 }
        var pick = valid.randomElement() ?? ceil(total)
        if abs(pick - total) < 0.005 { pick = ceil(total + 0.01) }
        return pick
    }

    func chargeCard() {
        guard let c = checkoutCustomer, c.state == .waitingPayment else {
            if checkoutCustomer != nil { toast("Scan everything first", .info) }
            return
        }
        guard !c.paysCash else {
            toast("This customer is paying cash — use the register", .warn)
            return
        }
        completeSale(given: 0)
    }

    func takeCash() {
        guard let c = checkoutCustomer, c.state == .waitingPayment else {
            if checkoutCustomer != nil { toast("Scan everything first", .info) }
            return
        }
        guard c.paysCash else {
            toast("This customer is paying by card — use the card reader", .warn)
            return
        }
        if game.manualChange {
            onRequestChange?(ChangeRequest(total: beltTotal, tendered: c.cashTendered))
        } else {
            completeSale(given: c.cashTendered - beltTotal)
        }
    }

    /// Finish the current sale. `given` is the change handed back (cash only).
    func completeSale(given: Double) {
        guard let c = checkoutCustomer else { return }
        var received = beltTotal
        if c.paysCash {
            let due = c.cashTendered - beltTotal
            received = c.cashTendered - given
            let diff = given - due
            if abs(diff) > 0.004 {
                stats.changeMistakes += 1
                if diff < 0 {
                    c.penalties += 1.5
                    toast("Short-changed them by \(formatMoney(-diff, symbol: symbol)) — they noticed", .bad)
                } else {
                    toast("Gave \(formatMoney(diff, symbol: symbol)) too much change", .warn)
                }
            } else {
                c.bonus += 0.15
            }
        }
        if c.patience < 0.3 { c.penalties += 0.8 }
        cash += received
        stats.revenue += received
        stats.served += 1
        stats.unitsSold += c.basket.count
        onMoneyPopup?(received)
        if display.showMoneyPopups {
            popup("+\(formatMoney(received, symbol: symbol))", at: SIMD3(layout.counter.center.x, 1.5, layout.counter.center.y),
                  color: StatusPalette.good(display.colorblind))
        }
        Feedback.shared.play(.cash)
        Feedback.shared.haptic(.success)
        clearBelt()
        checkoutCustomer = nil
        if let i = queue.firstIndex(where: { $0 === c }) { queue.remove(at: i) }
        reindexQueue()
        c.state = .leaving
        c.showBasket(true)
        c.path = nav.path(from: c.pos, to: layout.doorInside) + [layout.exitPoint]
    }
}
