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

    /// The basket shell is built once; only the pile of items inside is refreshed.
    func updateBasketVisual() {
        if basketShell == nil {
            let shell = SCNNode()
            shell.position.y = -0.37   // the top of the handle arc sits in the fist
            let b = MeshBuilder()
            let outer = Mats.tiled("basket\(basketColor)", gloss: 0.3) { Self.basketTexture(self.basketColor) }
            let inner = Mats.solid(Mats.shade(basketColor, 0.55), doubleSided: true)
            let rim = Mats.solid(Mats.shade(basketColor, 0.8), gloss: 0.3)
            // Tapered tub: wider at the top than the bottom.
            let tw: Float = 0.22, td: Float = 0.15, bw: Float = 0.18, bd: Float = 0.12, h: Float = 0.2
            let t = [SIMD3<Float>(-tw, h, td), SIMD3(tw, h, td), SIMD3(tw, h, -td), SIMD3(-tw, h, -td)]
            let o = [SIMD3<Float>(-bw, 0, bd), SIMD3(bw, 0, bd), SIMD3(bw, 0, -bd), SIMD3(-bw, 0, -bd)]
            let inset = SIMD3<Float>(0.97, 1, 0.97)
            let lift = SIMD3<Float>(0, 0.012, 0)
            let side: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>) = (SIMD2(0, 1), SIMD2(3, 1), SIMD2(3, 0), SIMD2(0, 0))
            for i in 0..<4 {
                let j = (i + 1) % 4
                b.quad(o[i], o[j], t[j], t[i], outer, uv: side)
                let ia: SIMD3<Float> = o[j] * inset + lift
                let ib: SIMD3<Float> = o[i] * inset + lift
                let ic: SIMD3<Float> = t[i] * inset
                let id: SIMD3<Float> = t[j] * inset
                b.quad(ia, ib, ic, id, inner)
            }
            b.quad(o[3], o[2], o[1], o[0], rim)                                  // underside
            b.quad(o[0] + lift, o[1] + lift, o[2] + lift, o[3] + lift, inner)    // floor
            b.box(0, h, td, tw * 2 + 0.03, 0.022, 0.022, rim)
            b.box(0, h, -td, tw * 2 + 0.03, 0.022, 0.022, rim)
            b.box(tw, h, 0, 0.022, 0.022, td * 2 + 0.03, rim)
            b.box(-tw, h, 0, 0.022, 0.022, td * 2 + 0.03, rim)
            if let tub = b.build() { shell.addChildNode(tub) }
            let handle = SCNNode(geometry: SCNTorus(ringRadius: 0.17, pipeRadius: 0.0085))
            handle.geometry?.firstMaterial = Mats.solid(0x1D2126, gloss: 0.4)
            handle.eulerAngles.x = Float.pi / 2
            handle.position.y = h
            shell.addChildNode(handle)
            let contents = SCNNode()
            contents.name = "contents"
            shell.addChildNode(contents)
            basketNode.addChildNode(shell)
            basketShell = shell
        }
        guard let shell = basketShell, let contents = shell.childNode(withName: "contents", recursively: false) else { return }
        contents.childNodes.forEach { $0.removeFromParentNode() }
        // Up to 10 things sitting in the basket
        let batch = MeshBatcher()
        for (i, it) in basket.prefix(10).enumerated() {
            guard let p = Catalog.product(it.product) else { continue }
            let s = p.shape.size
            let sc = min(1, 0.15 / max(s.w, s.h, s.d))
            var scale = matrix_identity_float4x4
            scale.columns.0.x = sc; scale.columns.1.y = sc; scale.columns.2.z = sc
            let x = -0.13 + Float(i % 4) * 0.087 + (i >= 8 ? 0.04 : 0)
            let z = -0.07 + Float((i / 4) % 2) * 0.12
            let y = 0.02 + Float(i / 8) * 0.08
            let m = Models.translate(x, y, z) * Models.rotate(Float(i) * 0.9, SIMD3(0, 1, 0)) * scale
            batch.add(Models.template(p, expired: it.expired), transform: m)
        }
        if let pile = batch.build() { contents.addChildNode(pile) }
        Models.setCategory(shell, 2)
        func noShadow(_ n: SCNNode) { n.castsShadow = false; n.childNodes.forEach(noShadow) }
        noShadow(shell)
    }

    static func basketTexture(_ color: UInt32) -> UIImage {
        let size = CGSize(width: 64, height: 64)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        return UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(hex: color).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            c.setFillColor(UIColor(hex: Mats.shade(color, 0.5)).cgColor)
            for i in 0..<4 {
                c.addPath(UIBezierPath(roundedRect: CGRect(x: 5 + i * 16, y: 14, width: 6, height: 40), cornerRadius: 3).cgPath)
            }
            c.fillPath()
            c.setFillColor(UIColor(white: 1, alpha: 0.12).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: 64, height: 6))
        }
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
        rig?.reach(now: time)
        flyFromFloor(it, to: cameraWorldPosition + SIMD3(0, -0.4, 0), duration: 0.16)
        removeFromFloor(it)
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
            noteMistake()
            return
        }
        if game.strictPlacement && (it.expired || slot.category != it.category) {
            let msg: String
            if it.expired {
                msg = "That \(p.name) is expired — it goes in the trash bin by the door, not on a shelf"
            } else if let here = slot.category {
                msg = "\(p.name) doesn't belong in \(here). Look for the \(it.category.uppercased()) sign"
            } else {
                msg = "\(p.name) doesn't go here. Look for the \(it.category.uppercased()) sign"
            }
            toast(msg, .warn)
            Feedback.shared.play(.bonk, volume: 0.6)
            Feedback.shared.haptic(.warning)
            noteMistake()
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

        rig?.reach(now: time)
        basket.removeAll { $0 === it }
        slot.items.append(it)
        slot.rebuild(pop: true)
        slot.refreshTag(visible: display.showShelfTags)
        flyToShelf(p, expired: it.expired, to: slot.nextItemWorldPosition)
        placedCount += 1

        let correct = slot.isCorrect
        if correct {
            let before = multiplier
            streak = time - lastCorrectAt <= GameWorld.comboWindow ? streak + 1 : 1
            lastCorrectAt = time
            bestStreak = max(bestStreak, streak)
            var points = 10 * multiplier
            if slot.isFull { points += 25 * multiplier }
            addPoints(points)
            if game.placementFeedback {
                Feedback.shared.play(slot.isFull ? .ding : .place, volume: 0.8)
                if slot.isFull { sparkle(at: slot.worldCenter, big: true) }
            } else {
                Feedback.shared.play(.place, volume: 0.7)
            }
            if multiplier > before {
                Feedback.shared.play(Sound.combo(multiplier), volume: 0.7)
                Feedback.shared.haptic(.medium)
            }
            if slot.isFull {
                fixtures[slot.fixture].refreshLabels(showLabels: display.showRowLabels, signScale: Float(display.signScale),
                                                     glow: scannerCategory != nil, glowCategory: scannerCategory)
                checkSection(slot.category)
            }
        } else {
            noteMistake()
            Feedback.shared.play(game.placementFeedback ? .bonk : .place, volume: 0.5)
            if game.placementFeedback && time - lastWrongToast > 3 {
                lastWrongToast = time
                toast(it.expired ? "That one's expired — it belongs in the trash" : "Hmm… that doesn't look like the right section", .warn)
            }
        }
        Feedback.shared.haptic(.light)
        basketChanged()
        checkComplete()
    }

    func addPoints(_ points: Int) {
        score += points
        onPoints?(points, multiplier)
    }

    /// A wrong attempt: breaks the combo and counts once (holding the button doesn't spam it).
    func noteMistake() {
        streak = 0
        if time - lastMistakeAt > 1.0 {
            lastMistakeAt = time
            mistakes += 1
        }
    }

    func sectionDone(_ cat: String) -> Bool {
        var any = false
        for f in fixtures {
            for sl in f.slots where sl.category == cat {
                any = true
                if !(sl.isFull && sl.isCorrect) { return false }
            }
        }
        return any
    }

    /// Celebrates a whole section (every spot under that label) being fully stocked.
    func checkSection(_ cat: String?) {
        guard let cat = cat, !completedSections.contains(cat), sectionDone(cat) else { return }
        completedSections.insert(cat)
        addPoints(200)
        toast("\(SectionStyle.icon(cat)) \(cat) fully stocked!  +200", .good)
        Feedback.shared.play(.section, volume: 0.8)
        Feedback.shared.haptic(.success)
        let spots = fixtures.flatMap { $0.slots }.filter { $0.category == cat }.prefix(10)
        for sl in spots { sparkle(at: sl.worldCenter, big: true) }
    }

    /// A copy of the product flying from your hand to its place on the shelf.
    func flyToShelf(_ p: Product, expired: Bool, to dest: SIMD3<Float>) {
        guard !display.reduceMotion else { return }
        let n = Models.productNode(p, expired: expired)
        let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        n.simdPosition = cameraWorldPosition + cameraNode.simdWorldFront * 0.35 + right * 0.18 + SIMD3(0, -0.28, 0)
        n.simdEulerAngles = SIMD3(0, yaw, 0)
        n.categoryBitMask = Models.categoryNoHit
        n.castsShadow = false
        scene.rootNode.addChildNode(n)
        let move = SCNAction.move(to: SCNVector3(dest.x, dest.y - p.shape.size.h / 2, dest.z), duration: 0.11)
        move.timingMode = .easeOut
        n.runAction(.sequence([move, .removeFromParentNode()]))
    }

    func takeBack(from slot: Slot) {
        guard basket.count < capacity else {
            toast("Basket full (\(basket.count)/\(capacity))", .warn)
            Feedback.shared.play(.bonk, volume: 0.6)
            return
        }
        guard let it = slot.items.popLast() else { return }
        rig?.reach(now: time)
        slot.rebuild()
        slot.refreshTag(visible: display.showShelfTags)
        if let cat = slot.category { completedSections.remove(cat) }
        fixtures[slot.fixture].refreshLabels(showLabels: display.showRowLabels, signScale: Float(display.signScale),
                                             glow: scannerCategory != nil, glowCategory: scannerCategory)
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
                if game.strictPlacement && it.expired { return "Expired — take it to the trash" }
                if game.strictPlacement && slot.category != it.category { return "✕ \(p.name) doesn't belong here" }
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
            addPoints(moved * 10)
            refreshSigns()
            for cat in Set(fixtures.flatMap { $0.slots }.compactMap { $0.category }) { checkSection(cat) }
            basketChanged()
            checkComplete()
        }
        skills.trigger(s, now: time, multiplier: skillMultiplier)
        if s != .autoSort && s != .magnet { Feedback.shared.play(.skill, volume: 0.6) }
        Feedback.shared.haptic(.medium)
        return true
    }

    private func pickUpQuiet(_ it: Item) {
        let dest = cameraWorldPosition + SIMD3(0, -0.4, 0)
        let d = Double(simd_distance(it.floorPos, SIMD2(dest.x, dest.z)))
        flyFromFloor(it, to: dest, duration: 0.15 + d * 0.06)
        removeFromFloor(it)
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
        n.castsShadow = false
        n.runAction(.sequence([.move(to: SCNVector3(p.x, p.y, p.z), duration: 0.45), .removeFromParentNode()]))
        sparkle(at: p, big: false)
    }

    // MARK: Completion

    func checkComplete() {
        guard !completed, remaining == 0 else { return }
        completed = true
        let t = elapsed
        let stars = t <= par ? 3 : t <= par * 1.5 ? 2 : 1
        let timeBonus = max(0, Int((1 - t / (par * 1.5)) * 1000))
        let cleanBonus = mistakes == 0 ? 300 : 0
        let final = score + timeBonus + cleanBonus
        let prev = ProgressStore.shared.complete(level, stars: stars, time: t, score: final, items: total, streak: bestStreak)
        Feedback.shared.play(.complete)
        Feedback.shared.haptic(.success)
        // A celebratory burst on a handful of shelves (not all of them: that would hitch).
        let full = fixtures.flatMap { $0.slots }.filter { $0.isFull }.shuffled().prefix(16)
        for s in full { sparkle(at: s.worldCenter, big: true) }
        let result = LevelResult(level: level, time: t, par: par, stars: stars, mistakes: mistakes, items: total,
                                 bestTime: prev.time, newBest: prev.time == nil || t < (prev.time ?? 0),
                                 score: final, baseScore: score, timeBonus: timeBonus, cleanBonus: cleanBonus,
                                 bestStreak: bestStreak, bestScore: prev.score,
                                 newBestScore: prev.score == nil || final > (prev.score ?? 0),
                                 next: Levels.next(after: level.id))
        onComplete?(result)
    }

    // MARK: Tutorial

    var tutorialText: String? {
        guard tutorialActive else { return nil }
        switch tutorialStep {
        case 0: return "This store is a disaster! Look at a product on the floor and tap it (or press the hand) to put it in your basket."
        case 1: return "Read the signs above the shelves and the labels on each shelf row to work out where it goes. Then tap a spot to place it."
        case 2: return "Identical items go together. Cold stuff lives in fridges and freezers. Tap the icons in your basket bar to choose what to place."
        case 3: return "Place items back to back to build a combo for more points. Fill every shelf to finish — faster means more stars. Skills on the right help when you're stuck."
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
