import SceneKit
import simd
import UIKit

extension GameWorld {
    // MARK: Basket

    var basketGroups: [BasketGroup] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        var sample: [String: Item] = [:]
        for it in basket {
            if counts[it.key] == nil { order.append(it.key); sample[it.key] = it }
            counts[it.key, default: 0] += 1
        }
        return order.compactMap { k -> BasketGroup? in
            guard let it = sample[k] else { return nil }
            return BasketGroup(key: k, product: it.product, expired: it.expired, count: counts[k] ?? 0)
        }
    }

    func select(_ key: String) {
        guard basket.contains(where: { $0.key == key }) else { return }
        selectedKey = key
        Feedback.shared.haptic(.light)
        if scannerCategory != nil, let it = basket.first(where: { $0.key == key }), !it.expired {
            scannerCategory = it.category
            refreshSigns()
        }
        basketChanged()
    }

    private func fixSelection() {
        if let k = selectedKey, basket.contains(where: { $0.key == k }) { return }
        selectedKey = basket.first?.key
    }

    func basketChanged() {
        fixSelection()
        updateBasketVisual()
        onBasketChanged?()
    }

    func updateBasketVisual() {
        basketNode.childNodes.forEach { $0.removeFromParentNode() }
        let b = SCNNode()
        let body = SCNNode(geometry: SCNBox(width: 0.42, height: 0.2, length: 0.3, chamferRadius: 0.025))
        body.geometry?.firstMaterial = Models.mat(0xD62828)
        body.position.y = 0.1
        b.addChildNode(body)
        let rim = SCNNode(geometry: SCNBox(width: 0.44, height: 0.03, length: 0.32, chamferRadius: 0.01))
        rim.geometry?.firstMaterial = Models.mat(0x9E1B1B)
        rim.position.y = 0.2
        b.addChildNode(rim)
        // Up to 8 things peeking out of the basket
        for (i, it) in basket.prefix(8).enumerated() {
            guard let p = Catalog.product(it.product) else { continue }
            let n = Models.productNode(p, expired: it.expired)
            let s = p.shape.size
            let sc = min(1, 0.16 / max(s.w, s.h, s.d))
            n.scale = SCNVector3(sc, sc, sc)
            n.position = SCNVector3(-0.13 + Float(i % 4) * 0.087, 0.12 + Float(i / 4) * 0.03, -0.06 + Float(i / 4) * 0.1)
            n.eulerAngles.y = Float(i) * 0.7
            b.addChildNode(n)
        }
        Models.setCategory(b, 2)
        basketNode.addChildNode(b)
    }

    // MARK: Actions

    func interact(_ t: Target?) {
        guard let t = t, !paused, !completed else { return }
        switch t {
        case let .item(id): pickUp(id)
        case let .slot(f, s):
            guard let slot = fixtures[safe: f]?.slots[safe: s] else { return }
            place(into: slot)
        case .bin: tossExpired()
        }
    }

    /// The Drop button: take one item back off a shelf, otherwise drop the selected item.
    func secondary(_ t: Target?) {
        guard !paused, !completed else { return }
        if let t = t, case let .slot(f, s) = t, let slot = fixtures[safe: f]?.slots[safe: s], !slot.items.isEmpty {
            takeBack(from: slot)
            return
        }
        dropSelected()
    }

    func pickUp(_ id: Int) {
        guard let it = floorItems[id] else { return }
        guard basket.count < capacity else {
            toast("Basket full (\(basket.count)/\(capacity)) — put some things away first", .warn)
            Feedback.shared.play(.bonk, volume: 0.6)
            return
        }
        floorItems[id] = nil
        if let n = it.node {
            n.name = nil
            let dest = cameraWorldPosition + SIMD3(0, -0.4, 0)
            n.runAction(.sequence([
                .group([.move(to: SCNVector3(dest.x, dest.y, dest.z), duration: 0.16), .scale(to: 0.2, duration: 0.16)]),
                .removeFromParentNode()]))
        }
        it.node = nil
        basket.append(it)
        pickedCount += 1
        if selectedKey == nil { selectedKey = it.key }
        Feedback.shared.play(.pop, volume: 0.7)
        Feedback.shared.haptic(.light)
        basketChanged()
    }

    /// Which basket item to place in a slot.
    private func chooseItem(for slot: Slot) -> Item? {
        if game.autoMatch, let k = slot.key, let it = basket.first(where: { $0.key == k }) { return it }
        if let k = selectedKey, let it = basket.first(where: { $0.key == k }) { return it }
        return basket.first
    }

    func place(into slot: Slot) {
        guard let it = chooseItem(for: slot), let p = Catalog.product(it.product) else {
            toast("Your basket is empty — grab items off the floor", .info)
            return
        }
        let fx = fixtures[slot.fixture]
        guard fx.kind == p.fixture else {
            let need = p.fixture == .shelf ? "a regular shelf" : "a \(p.fixture.label.lowercased())"
            toast("\(p.name) goes on \(need)", .warn)
            Feedback.shared.play(.bonk, volume: 0.6)
            return
        }
        if let k = slot.key, k != it.key {
            let other = slot.items.first.flatMap { Catalog.product($0.product)?.name } ?? "something else"
            toast("That spot has \(other) — use Drop to take them out first", .warn)
            Feedback.shared.play(.bonk, volume: 0.6)
            return
        }
        if slot.items.count > 0 && slot.isFull {
            toast("That spot is full", .info)
            Feedback.shared.play(.bonk, volume: 0.5)
            return
        }
        // Keep identical items together when they're going to the right section.
        if game.keepTogether && slot.items.isEmpty && !it.expired && slot.category == it.category {
            let existing = fixtures.flatMap { $0.slots }.first {
                $0 !== slot && $0.key == it.key && $0.isCorrect && !$0.isFull
            }
            if existing != nil {
                toast("\(p.name) already has a spot in this section that isn't full — keep them together", .warn)
                Feedback.shared.play(.bonk, volume: 0.5)
                return
            }
        }

        basket.removeAll { $0 === it }
        slot.items.append(it)
        slot.rebuild()
        slot.refreshTag(visible: display.showShelfTags)
        placedCount += 1

        let correct = slot.isCorrect
        if !correct { mistakes += 1 }
        if game.placementFeedback {
            if correct {
                Feedback.shared.play(slot.isFull ? .ding : .place, volume: 0.8)
                sparkle(at: slot.worldCenter, big: slot.isFull)
            } else {
                Feedback.shared.play(.bonk, volume: 0.5)
                if time - lastWrongToast > 3 {
                    lastWrongToast = time
                    toast(it.expired ? "That one's expired — it belongs in the trash" : "Hmm… that doesn't look like the right section", .warn)
                }
            }
        } else {
            Feedback.shared.play(.place, volume: 0.7)
        }
        Feedback.shared.haptic(.light)
        basketChanged()
        checkComplete()
    }

    func takeBack(from slot: Slot) {
        guard basket.count < capacity else {
            toast("Basket full (\(basket.count)/\(capacity))", .warn)
            Feedback.shared.play(.bonk, volume: 0.6)
            return
        }
        guard let it = slot.items.popLast() else { return }
        slot.rebuild()
        slot.refreshTag(visible: display.showShelfTags)
        basket.append(it)
        selectedKey = it.key
        Feedback.shared.play(.pickup, volume: 0.6)
        basketChanged()
    }

    func dropSelected() {
        guard let k = selectedKey, let it = basket.first(where: { $0.key == k }) else { return }
        let forward = SIMD2<Float>(-sin(yaw), -cos(yaw))
        var spot = playerPos + forward * 0.6
        if !layout.isOpen(spot, clearance: 0.15) { spot = playerPos }
        basket.removeAll { $0 === it }
        placeOnFloor(it, at: spot, yaw: yaw, tipped: false)
        Feedback.shared.play(.place, volume: 0.5)
        basketChanged()
    }

    func tossExpired() {
        let bad = basket.filter { $0.expired }
        guard !bad.isEmpty else {
            toast(basket.isEmpty ? "Only expired items go in the trash" : "That's all still good — only expired items go in the trash", .info)
            return
        }
        basket.removeAll { $0.expired }
        binned += bad.count
        for it in bad { items[it.id] = nil }
        Feedback.shared.play(.toss)
        toast("Tossed \(bad.count) expired item\(bad.count == 1 ? "" : "s")", .good)
        basketChanged()
        checkComplete()
    }

    // MARK: Prompts

    func prompt(for t: Target?) -> String? {
        guard let t = t else { return nil }
        switch t {
        case let .item(id):
            guard let it = floorItems[id], let p = Catalog.product(it.product) else { return nil }
            let name = it.expired ? "\(p.name) (expired)" : p.name
            return basket.count >= capacity ? "\(name)  ·  basket full" : "Pick up \(name)"
        case let .slot(f, s):
            guard let fx = fixtures[safe: f], let slot = fx.slots[safe: s] else { return nil }
            if let it = chooseItem(for: slot), let p = Catalog.product(it.product) {
                if fx.kind != p.fixture { return "\(p.name) doesn't go in a \(fx.kind.label.lowercased())" }
                if let k = slot.key, k != it.key { return "Spot has \(slot.items.first.flatMap { Catalog.product($0.product)?.name } ?? "other stock")  ·  Drop takes one out" }
                if slot.isFull { return "Full" }
                return "Place \(p.name)\(it.expired ? " (expired)" : "")"
            }
            if let first = slot.items.first, let p = Catalog.product(first.product) {
                return "\(p.name) ×\(slot.count)  ·  Drop takes one out"
            }
            return "Empty spot"
        case .bin:
            let n = basket.filter { $0.expired }.count
            return n > 0 ? "Throw away \(n) expired item\(n == 1 ? "" : "s")" : "Trash — expired items only"
        }
    }

    // MARK: Skills

    var skillMultiplier: Double { game.skillCooldown }

    @discardableResult
    func useSkill(_ s: SkillID) -> Bool {
        guard !paused, !completed else { return false }
        guard skills.isReady(s, now: time) else {
            toast("\(s.name) ready in \(Int(ceil(skills.remaining(s, now: time))))s", .info)
            return false
        }
        switch s {
        case .sprint, .freeze:
            break
        case .magnet:
            let room = capacity - basket.count
            guard room > 0 else { toast("Basket's already full", .warn); return false }
            let me = SIMD2<Float>(playerPos.x, playerPos.y)
            let near = floorItems.values
                .map { ($0, simd_distance($0.floorPos, me)) }
                .filter { $0.1 < 5.5 }
                .sorted { $0.1 < $1.1 }
                .prefix(room)
            guard !near.isEmpty else { toast("Nothing nearby to pull in", .warn); return false }
            for (it, _) in near { pickUpQuiet(it) }
            Feedback.shared.play(.magnet)
            toast("Pulled in \(near.count) item\(near.count == 1 ? "" : "s")", .good)
            basketChanged()
        case .scanner:
            guard let k = selectedKey, let it = basket.first(where: { $0.key == k }) else {
                toast("Select an item in your basket first", .warn)
                return false
            }
            if it.expired {
                toast("Expired items go in the trash bin by the door", .info)
            } else {
                scannerCategory = it.category
                refreshSigns()
            }
        case .autoSort:
            var moved = 0
            for it in basket where moved < 5 {
                if it.expired {
                    basket.removeAll { $0 === it }
                    binned += 1
                    items[it.id] = nil
                    moved += 1
                    continue
                }
                guard let slot = correctSlot(for: it) else { continue }
                basket.removeAll { $0 === it }
                slot.items.append(it)
                slot.rebuild()
                slot.refreshTag(visible: display.showShelfTags)
                flyEffect(it, to: slot.worldCenter)
                moved += 1
            }
            guard moved > 0 else { toast("No room for these items on their shelves", .warn); return false }
            Feedback.shared.play(.ding)
            toast("Auto-sorted \(moved) item\(moved == 1 ? "" : "s")", .good)
            basketChanged()
            checkComplete()
        }
        skills.trigger(s, now: time, multiplier: skillMultiplier)
        if s != .autoSort && s != .magnet { Feedback.shared.play(.skill, volume: 0.6) }
        Feedback.shared.haptic(.medium)
        return true
    }

    private func pickUpQuiet(_ it: Item) {
        floorItems[it.id] = nil
        if let n = it.node {
            n.name = nil
            let dest = cameraWorldPosition + SIMD3(0, -0.4, 0)
            let d = Double(simd_distance(SIMD2(n.simdPosition.x, n.simdPosition.z), SIMD2(dest.x, dest.z)))
            n.runAction(.sequence([
                .group([.move(to: SCNVector3(dest.x, dest.y, dest.z), duration: 0.15 + d * 0.06), .scale(to: 0.2, duration: 0.3)]),
                .removeFromParentNode()]))
        }
        it.node = nil
        basket.append(it)
        pickedCount += 1
    }

    /// A slot where this item would be correct: its existing spot first, then an empty one in its section.
    func correctSlot(for it: Item) -> Slot? {
        let all = fixtures.flatMap { f in f.slots.map { (f, $0) } }
        if let s = all.first(where: { $0.1.key == it.key && $0.1.isCorrect && !$0.1.isFull })?.1 { return s }
        guard let p = Catalog.product(it.product) else { return nil }
        return all.first(where: { $0.0.kind == p.fixture && $0.1.items.isEmpty && $0.1.category == it.category })?.1
    }

    private func flyEffect(_ it: Item, to p: SIMD3<Float>) {
        guard let prod = Catalog.product(it.product) else { return }
        let n = Models.productNode(prod)
        n.simdPosition = cameraWorldPosition + SIMD3(0, -0.4, 0)
        Models.setCategory(n, Models.categoryNoHit)
        scene.rootNode.addChildNode(n)
        n.runAction(.sequence([.move(to: SCNVector3(p.x, p.y, p.z), duration: 0.45), .removeFromParentNode()]))
        sparkle(at: p, big: false)
    }

    // MARK: Completion

    func checkComplete() {
        guard !completed, remaining == 0 else { return }
        completed = true
        let t = elapsed
        let stars = t <= par ? 3 : t <= par * 1.5 ? 2 : 1
        let prev = ProgressStore.shared.complete(level, stars: stars, time: t)
        Feedback.shared.play(.complete)
        Feedback.shared.haptic(.success)
        for f in fixtures { for s in f.slots where s.isFull { sparkle(at: s.worldCenter, big: true) } }
        let result = LevelResult(level: level, time: t, par: par, stars: stars, mistakes: mistakes, items: total,
                                 bestTime: prev, newBest: prev == nil || t < prev!, next: Levels.next(after: level.id))
        onComplete?(result)
    }

    // MARK: Tutorial

    var tutorialText: String? {
        guard tutorialActive else { return nil }
        switch tutorialStep {
        case 0: return "This store is a disaster! Look at a product on the floor and tap it (or press the hand) to put it in your basket."
        case 1: return "Read the signs above the shelves and the labels on each shelf row to work out where it goes. Then tap a spot to place it."
        case 2: return "Identical items go together. Cold stuff lives in fridges and freezers. Tap the icons in your basket bar to choose what to place."
        case 3: return "Get every item from the floor into its right section to finish. Faster = more stars. Skills on the right help when you're stuck."
        default: return nil
        }
    }

    func updateTutorial() {
        guard tutorialActive else { return }
        switch tutorialStep {
        case 0: if pickedCount > 0 { tutorialStep = 1 }
        case 1: if placedCount > 0 { tutorialStep = 2 }
        case 2: if placedCount >= 4 { tutorialStep = 3 }
        case 3:
            if placedCount >= 10 {
                tutorialStep = 4
                tutorialActive = false
                ProgressStore.shared.markTutorialSeen()
            }
        default: tutorialActive = false
        }
    }
}
