import SceneKit
import simd
import UIKit

enum Target: Equatable {
    case item(Int)
    case slot(Int, Int)
    case bin
}

enum ToastStyle { case info, good, warn, bad }

struct BasketGroup: Equatable {
    let key: String
    let product: String
    let expired: Bool
    let count: Int
}

final class FloorChunk {
    var items: [Int] = []
    var visual: SCNNode?
    var shadow: SCNNode?
    var dirty = false
    var baked: [Int: MeshBatcher.Baked] = [:]
    var bakedShadow: [Int: MeshBatcher.Baked] = [:]
}

@MainActor
final class GameWorld {
    // MARK: Setup
    let level: OrgLevel
    let layout: StoreLayout
    let scene = SCNScene()
    let playerNode = SCNNode()
    let cameraNode = SCNNode()
    let basketNode = SCNNode()
    let highlightNode: SCNNode
    var fixtures: [Fixture] = []
    var playerRects: [Rect] = []
    let eyeHeight: Float = 1.62

    // MARK: Player
    var playerPos: SIMD2<Float>
    var yaw: Float = 0
    var pitch: Float = -0.25
    var targetYaw: Float = 0
    var targetPitch: Float = -0.25
    var bobPhase: Float = 0
    var velocity = SIMD2<Float>(0, 0)

    // MARK: Items
    var items: [Int: Item] = [:]
    var floorItems: [Int: Item] = [:]
    var basket: [Item] = []
    var selectedKey: String?
    var binned = 0
    var total = 0
    var nextItemID = 1
    var activeProducts: [String] = []
    /// How many shelf spots each product fills when the level is done (shelves end up full).
    var slotPlan: [String: Int] = [:]
    var chunks: [Int: FloorChunk] = [:]
    var chunksDirty = false
    var lastFOV: Double = 0
    var rig: FirstPersonRig?
    var basketShell: SCNNode?
    var basketColor: UInt32 = 0xD62828
    var lookDelta = SIMD2<Float>(0, 0)
    var lastStep = 0

    // MARK: Progress
    var elapsed: Double = 0
    var mistakes = 0
    var time: Double = 0
    var paused = false
    var completed = false
    var skills = SkillSet()
    var scannerCategory: String?
    var lastWrongToast: Double = -10
    var placedCount = 0
    var pickedCount = 0
    var tutorialActive = false
    var tutorialStep = 0

    // MARK: Score & combo
    var score = 0
    var streak = 0
    var bestStreak = 0
    var lastCorrectAt: Double = -100
    var lastMistakeAt: Double = -100
    var completedSections: Set<String> = []
    static let comboWindow = 4.5
    /// x1…x5: goes up every 4 correct placements in a row.
    var multiplier: Int { min(5, 1 + streak / 4) }
    /// How much of the combo timer is left (1 = just placed, 0 = about to drop).
    var comboFraction: Double { streak > 0 ? max(0, 1 - (time - lastCorrectAt) / GameWorld.comboWindow) : 0 }

    // MARK: Callbacks
    var onToast: ((String, ToastStyle) -> Void)?
    var onComplete: ((LevelResult) -> Void)?
    var onBasketChanged: (() -> Void)?
    var onPoints: ((Int, Int) -> Void)?

    var display: DisplaySettings { SettingsStore.shared.display }
    var game: GameSettings { SettingsStore.shared.game }
    var capacity: Int { max(3, Int(game.basketCapacity.rounded())) }
    var par: Double { (45 + Double(total) * 2.5) * game.parTimeScale }

    // MARK: Init

    init(level: OrgLevel, save: LevelSave?) {
        self.level = level

        // Which products this run uses ("Mess size" scales how many kinds of stock there are).
        let n = level.products.count
        let want = Int((Double(n) * SettingsStore.shared.game.messSize).rounded())
        let active = Array(level.products.prefix(max(min(4, n), min(n, want))))
        activeProducts = active

        // Plan shelf rows: each category gets enough rows for its products.
        var groups: [(kind: FixtureKind, cat: String, count: Int)] = []
        for id in active {
            guard let p = Catalog.product(id) else { continue }
            if let i = groups.firstIndex(where: { $0.kind == p.fixture && $0.cat == p.category }) {
                groups[i].count += 1
            } else {
                groups.append((p.fixture, p.category, 1))
            }
        }
        var rowQueues: [FixtureKind: [String]] = [:]
        for g in groups {
            let rows = Int(ceil(Double(g.count * level.slotsPerProduct) / 2))
            rowQueues[g.kind, default: []] += Array(repeating: g.cat, count: rows)
        }
        func units(_ k: FixtureKind) -> Int { Int(ceil(Double(rowQueues[k]?.count ?? 0) / 3)) }
        let cold = Array(repeating: FixtureKind.fridge, count: units(.fridge)) + Array(repeating: FixtureKind.freezer, count: units(.freezer))
        // Room grows gently with the amount of stock, so the mess always has space to spread out.
        let extra = Float(active.count / 6) + (level.stage == 3 ? 1 : 0)
        layout = StoreLayout.fit(cold: cold, shelves: max(1, units(.shelf)), minWidth: 8 + extra * 0.5, minDepth: 10 + extra * 0.5)
        playerPos = layout.playerStart

        let hl = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
        let hm = SCNMaterial()
        hm.diffuse.contents = UIColor(white: 1, alpha: 0.16)
        hm.lightingModel = .constant
        hm.writesToDepthBuffer = false
        hm.transparencyMode = .dualLayer
        hl.geometry?.firstMaterial = hm
        hl.categoryBitMask = Models.categoryNoHit
        hl.renderingOrder = 50
        hl.isHidden = true
        highlightNode = hl

        buildScene()
        playerRects = layout.solidRects

        // Label the rows. Leftover rows on the last unit of a kind go to that kind's last
        // section, so every row is labeled and every spot gets filled.
        var queues = rowQueues
        var lastCat: [FixtureKind: String] = [:]
        for g in groups { lastCat[g.kind] = g.cat }
        var catSlots: [String: Int] = [:]
        for f in fixtures {
            var cats: [String?] = []
            for _ in 0..<3 {
                var cat: String? = lastCat[f.kind]
                if var q = queues[f.kind], !q.isEmpty {
                    cat = q.removeFirst()
                    queues[f.kind] = q
                }
                cats.append(cat)
                if let c = cat { catSlots[f.kind.rawValue + "|" + c, default: 0] += 2 }
            }
            f.setRows(cats, showLabels: display.showRowLabels, signScale: Float(display.signScale))
        }
        // Share each section's spots among its products.
        for g in groups {
            let prods = active.filter { Catalog.product($0)?.fixture == g.kind && Catalog.product($0)?.category == g.cat }
            guard !prods.isEmpty else { continue }
            let slots = catSlots[g.kind.rawValue + "|" + g.cat] ?? prods.count * level.slotsPerProduct
            for (i, id) in prods.enumerated() {
                slotPlan[id] = slots / prods.count + (i < slots % prods.count ? 1 : 0)
            }
        }

        if let s = save, s.fixtureCount == fixtures.count, s.layoutVersion == LevelSave.currentLayout, restore(s) {
            // restored exactly
        } else {
            generateMess()
            // The store changed since this save (an update, or different game rules):
            // keep the time, score and everything that was already shelved correctly.
            if let s = save, s.isUsable { carryOver(s) }
        }
        tutorialActive = level.index == 0 && game.showTutorial && !ProgressStore.shared.data.seenTutorial && save == nil
        rebuildChunks()
        updateBasketVisual()
    }

    // MARK: Mess generation

    private func generateMess() {
        var list: [Item] = []
        // Exactly enough stock to fill every planned spot: the store ends up fully stocked.
        for id in activeProducts {
            guard let p = Catalog.product(id) else { continue }
            let n = Slot.capacity(for: p) * max(1, slotPlan[id] ?? level.slotsPerProduct)
            for _ in 0..<n { list.append(makeItem(id, expired: false)) }
        }
        if game.expiredItems && level.expired > 0 {
            for _ in 0..<level.expired {
                if let id = activeProducts.randomElement() { list.append(makeItem(id, expired: true)) }
            }
        }
        total = list.count
        list.shuffle()

        // Some products start on the wrong shelves.
        if game.misplacedItems && level.misplaced > 0 {
            let k = Int((Double(activeProducts.count) * level.misplaced).rounded())
            for id in activeProducts.shuffled().prefix(k) {
                guard let p = Catalog.product(id) else { continue }
                let candidates = fixtures.filter { $0.kind == p.fixture }.flatMap { $0.slots }
                    .filter { $0.items.isEmpty && $0.category != p.category }
                guard let slot = candidates.randomElement() else { continue }
                let mine = list.filter { $0.product == id && !$0.expired }
                let take = Array(mine.prefix(min(3, max(1, mine.count / 2))))
                for it in take {
                    slot.items.append(it)
                    list.removeAll { $0 === it }
                }
                slot.rebuild()
                slot.refreshTag(visible: display.showShelfTags)
            }
        }

        // Scatter the rest in messy piles.
        var piles: [SIMD2<Float>] = []
        let pileCount = max(3, list.count / 9)
        var guardCount = 0
        while piles.count < pileCount && guardCount < 2000 {
            guardCount += 1
            let p = SIMD2<Float>(Float.random(in: 0.6...(layout.width - 0.6)), Float.random(in: 0.6...(layout.depth - 0.6)))
            if layout.isOpen(p, clearance: 0.4) && simd_distance(p, layout.playerStart) > 1.0 { piles.append(p) }
        }
        if piles.isEmpty { piles = [layout.playerStart + SIMD2(0, -1)] }
        for it in list {
            let c = piles.randomElement()!
            var spot = c
            for _ in 0..<14 {
                let a = Float.random(in: 0...(2 * .pi)), r = Float.random(in: 0...1.1)
                let q = c + SIMD2(cos(a), sin(a)) * r
                if layout.isOpen(q, clearance: 0.25) { spot = q; break }
            }
            let tipped = game.tippedItems && Float.random(in: 0...1) < 0.35
            placeOnFloor(it, at: spot, yaw: Float.random(in: 0...(2 * .pi)), tipped: tipped)
        }
    }

    private func makeItem(_ product: String, expired: Bool) -> Item {
        let it = Item(id: nextItemID, product: product, expired: expired)
        nextItemID += 1
        items[it.id] = it
        return it
    }

    /// Floor items are drawn in merged chunks (one mesh per 4 m square). Each item only keeps
    /// an invisible hit box so it can still be tapped individually.
    func placeOnFloor(_ it: Item, at p: SIMD2<Float>, yaw: Float, tipped: Bool) {
        guard let prod = Catalog.product(it.product) else { return }
        let s = prod.shape.size
        let bw = max(0.2, tipped ? s.h : s.w), bh = max(0.18, tipped ? s.w : s.h), bd = max(0.2, s.d)
        it.hitHalf = SIMD3(bw / 2, bh / 2, bd / 2)
        it.hitCenter = SIMD3(tipped ? -s.h / 2 : 0, bh / 2, 0)
        it.floorPos = p
        it.yaw = yaw
        it.tipped = tipped
        floorItems[it.id] = it
        let key = chunkKey(p)
        it.chunk = key
        let c: FloorChunk
        if let existing = chunks[key] { c = existing } else { c = FloorChunk(); chunks[key] = c }
        c.items.append(it.id)
        c.dirty = true
        chunksDirty = true
    }

    func removeFromFloor(_ it: Item) {
        floorItems[it.id] = nil
        it.node?.removeFromParentNode()
        it.node = nil
        if let c = chunks[it.chunk] {
            c.items.removeAll { $0 == it.id }
            c.baked[it.id] = nil
            c.bakedShadow[it.id] = nil
            c.dirty = true
            chunksDirty = true
        }
    }

    func chunkKey(_ p: SIMD2<Float>) -> Int {
        Int(floor(p.x / 4)) * 1000 + Int(floor(p.y / 4))
    }

    /// Rebuilds the merged meshes of chunks that changed. During play at most `limit` chunks
    /// are rebuilt per frame so a big Magnet pull never causes a hitch.
    func rebuildChunks(limit: Int = .max) {
        guard chunksDirty else { return }
        var done = 0
        for c in chunks.values where c.dirty {
            if done >= limit { return }   // leave chunksDirty set; finish next frame
            done += 1
            c.dirty = false
            c.visual?.removeFromParentNode()
            c.visual = nil
            c.shadow?.removeFromParentNode()
            c.shadow = nil
            guard !c.items.isEmpty else { continue }
            let batch = MeshBatcher()
            let shadows = MeshBatcher()
            for id in c.items {
                guard let it = floorItems[id], let p = Catalog.product(it.product) else { continue }
                if c.baked[id] == nil {
                    var m = Models.translate(it.floorPos.x, 0, it.floorPos.y) * Models.rotate(it.yaw, SIMD3(0, 1, 0))
                    if it.tipped {
                        m = m * Models.translate(0, p.shape.size.w / 2, 0) * Models.rotate(Float.pi / 2, SIMD3(0, 0, 1))
                    }
                    c.baked[id] = MeshBatcher.bake(Models.template(p, expired: it.expired), transform: m)
                    let sz = p.shape.size
                    let fx = ((it.tipped ? sz.h : sz.w) + 0.08) * 1.25
                    let fz = (sz.d + 0.08) * 1.25
                    var sm = Models.translate(it.floorPos.x, 0.003, it.floorPos.y) * Models.rotate(it.yaw, SIMD3(0, 1, 0))
                    if it.tipped { sm = sm * Models.translate(-sz.h / 2, 0, 0) }
                    var scale = matrix_identity_float4x4
                    scale.columns.0.x = fx
                    scale.columns.2.z = fz
                    c.bakedShadow[id] = MeshBatcher.bake(ContactShadow.mesh, transform: sm * scale)
                }
                if let b = c.baked[id] { batch.add(b) }
                if let b = c.bakedShadow[id] { shadows.add(b) }
            }
            if let merged = batch.build() {
                Models.setCategory(merged, Models.categoryNoHit)
                scene.rootNode.addChildNode(merged)
                c.visual = merged
            }
            if let sh = shadows.build() {
                sh.renderingOrder = 5
                Models.setCategory(sh, Models.categoryNoHit)
                scene.rootNode.addChildNode(sh)
                c.shadow = sh
            }
        }
        chunksDirty = false
    }

    /// A temporary copy of a floor item flying to a point (pickup / magnet animation).
    func flyFromFloor(_ it: Item, to dest: SIMD3<Float>, duration: Double) {
        guard let p = Catalog.product(it.product) else { return }
        let n = Models.productNode(p, expired: it.expired)
        n.simdPosition = SIMD3(it.floorPos.x, 0.05, it.floorPos.y)
        n.simdEulerAngles = SIMD3(0, it.yaw, 0)
        n.categoryBitMask = Models.categoryNoHit
        scene.rootNode.addChildNode(n)
        n.runAction(.sequence([
            .group([.move(to: SCNVector3(dest.x, dest.y, dest.z), duration: duration), .scale(to: 0.2, duration: duration)]),
            .removeFromParentNode()]))
    }

    // MARK: Save / restore

    func snapshot() {
        guard !completed else { return }
        var saves: [ItemSave] = []
        for it in floorItems.values {
            saves.append(ItemSave(product: it.product, expired: it.expired, loc: 0, x: it.floorPos.x, z: it.floorPos.y, yaw: it.yaw, tipped: it.tipped))
        }
        for it in basket { saves.append(ItemSave(product: it.product, expired: it.expired, loc: 1)) }
        for f in fixtures {
            for s in f.slots {
                let ok = s.isCorrect
                for it in s.items { saves.append(ItemSave(product: it.product, expired: it.expired, loc: 2, f: f.index, s: s.index, ok: ok)) }
            }
        }
        var save = LevelSave(levelID: level.id, elapsed: elapsed, mistakes: mistakes, binned: binned,
                             total: total, fixtureCount: fixtures.count, items: saves)
        save.score = score
        save.bestStreak = bestStreak
        save.px = playerPos.x
        save.pz = playerPos.y
        save.yaw = targetYaw
        save.pitch = targetPitch
        save.streak = comboFraction > 0 ? streak : 0
        save.selected = selectedKey
        save.cooldowns = skills.cooldownsLeft(now: time)
        ProgressStore.shared.store(save)
    }

    private func restore(_ s: LevelSave) -> Bool {
        for sv in s.items where Catalog.product(sv.product) == nil { return false }
        elapsed = s.elapsed
        mistakes = s.mistakes
        binned = s.binned
        total = s.total
        var touched: Set<ObjectIdentifier> = []
        for sv in s.items {
            let it = makeItem(sv.product, expired: sv.expired)
            switch sv.loc {
            case 1:
                basket.append(it)
            case 2:
                if let slot = fixtures[safe: sv.f]?.slots[safe: sv.s] {
                    slot.items.append(it)
                    touched.insert(ObjectIdentifier(slot))
                } else {
                    placeOnFloor(it, at: layout.playerStart, yaw: 0, tipped: false)
                }
            default:
                placeOnFloor(it, at: SIMD2(sv.x, sv.z), yaw: sv.yaw, tipped: sv.tipped)
            }
        }
        for f in fixtures {
            for slot in f.slots where touched.contains(ObjectIdentifier(slot)) {
                slot.rebuild()
                slot.refreshTag(visible: display.showShelfTags)
            }
        }
        selectedKey = basket.first?.key
        if let sel = s.selected, basket.contains(where: { $0.key == sel }) { selectedKey = sel }
        restoreRun(s)
        if let x = s.px, let z = s.pz, layout.isOpen(SIMD2(x, z), clearance: 0.2) {
            playerPos = SIMD2(x, z)
            yaw = s.yaw ?? yaw
            targetYaw = yaw
            pitch = max(-1.35, min(1.35, s.pitch ?? pitch))
            targetPitch = pitch
            playerNode.simdPosition = SIMD3(x, 0, z)
            playerNode.simdEulerAngles = SIMD3(0, yaw, 0)
            cameraNode.simdEulerAngles = SIMD3(pitch, 0, 0)
        }
        for cat in Set(fixtures.flatMap { $0.slots }.compactMap { $0.category }) where sectionDone(cat) {
            completedSections.insert(cat)
        }
        refreshSigns()
        return true
    }

    /// Clock, score, combo and cooldowns from a save.
    private func restoreRun(_ s: LevelSave) {
        elapsed = s.elapsed
        mistakes = s.mistakes
        score = s.score ?? 0
        bestStreak = s.bestStreak ?? 0
        streak = s.streak ?? 0
        if streak > 0 { lastCorrectAt = time }   // a fresh combo window to pick it back up
        if let c = s.cooldowns { skills.restore(c, now: time) }
    }

    /// Applies an older save to a freshly generated mess: whatever was already sorted stays sorted.
    private func carryOver(_ s: LevelSave) {
        var shelved: [String: Int] = [:]
        for sv in s.items where sv.loc == 2 && sv.ok == true && !sv.expired { shelved[sv.product, default: 0] += 1 }
        var toBin = s.binned
        var touched: Set<ObjectIdentifier> = []
        for it in floorItems.values.sorted(by: { $0.id < $1.id }) {
            if it.expired {
                guard toBin > 0 else { continue }
                toBin -= 1
                removeFromFloor(it)
                items[it.id] = nil
                binned += 1
                continue
            }
            guard let left = shelved[it.product], left > 0, let slot = correctSlot(for: it) else { continue }
            shelved[it.product] = left - 1
            removeFromFloor(it)
            slot.items.append(it)
            touched.insert(ObjectIdentifier(slot))
        }
        for f in fixtures {
            for slot in f.slots where touched.contains(ObjectIdentifier(slot)) {
                slot.rebuild()
                slot.refreshTag(visible: display.showShelfTags)
            }
        }
        restoreRun(s)
        for cat in Set(fixtures.flatMap { $0.slots }.compactMap { $0.category }) where sectionDone(cat) {
            completedSections.insert(cat)
        }
        refreshSigns()
    }

    // MARK: Per-frame

    func look(dx: Float, dy: Float) {
        let s = Float(display.lookSensitivity) * 0.0055
        let sy = s * Float(display.lookSensitivityY) * (display.invertY ? -1 : 1)
        lookDelta = SIMD2(dx, dy)
        targetYaw -= dx * s
        targetPitch = max(-1.35, min(1.35, targetPitch - dy * sy))
    }

    func update(dt rawDt: Double, move: SIMD2<Float>) {
        guard !paused else { return }
        let dt = min(rawDt, 0.05)
        time += dt
        if !completed && !skills.isActive(.freeze, now: time) { elapsed += dt }
        updatePlayer(dt: Float(dt), move: move)
        if streak > 0 && time - lastCorrectAt > GameWorld.comboWindow { streak = 0 }
        rebuildChunks(limit: 2)
        if scannerCategory != nil && !skills.isActive(.scanner, now: time) {
            scannerCategory = nil
            refreshSigns()
        }
        updateTutorial()
    }

    private func updatePlayer(dt: Float, move: SIMD2<Float>) {
        let d = display
        let s = Float(d.cameraSmoothing)
        let k: Float = s < 0.02 ? 1 : 1 - pow(s, dt * 30)
        yaw += (targetYaw - yaw) * k
        pitch += (targetPitch - pitch) * k
        playerNode.simdEulerAngles = SIMD3(0, yaw, 0)

        var mv = move
        let len = simd_length(mv)
        if len > 1 { mv /= len }
        let sprinting = skills.isActive(.sprint, now: time)
        let speed: Float = 3.0 * Float(game.walkSpeed) * (sprinting ? 1.8 : 1)
        let forward = SIMD2<Float>(-sin(yaw), -cos(yaw))
        let right = SIMD2<Float>(cos(yaw), -sin(yaw))
        // Ease in/out of walking like a person would (quick to start, a touch slower to stop).
        let wanted = (forward * mv.y + right * mv.x) * speed
        let rate: Float = simd_length(wanted) > simd_length(velocity) ? 14 : 10
        velocity += (wanted - velocity) * min(1, dt * rate)
        if simd_length(velocity) < 0.01 && simd_length(wanted) == 0 { velocity = .zero }
        let resolved = resolveCollisions(playerPos + velocity * dt)
        if dt > 0 { velocity = (resolved - playerPos) / dt }   // don't keep pushing into walls
        playerPos = resolved
        playerNode.simdPosition = SIMD3(playerPos.x, 0, playerPos.y)

        let walkAmount = min(1, simd_length(velocity) / max(0.1, 3.0 * Float(game.walkSpeed)))
        let moving = walkAmount > 0.08
        if moving { bobPhase += dt * simd_length(velocity) * 3.4 }
        let amount = walkAmount
        let bob: Float = (d.headBob && !d.reduceMotion && moving) ? abs(sin(bobPhase)) * 0.045 * amount - 0.02 * amount : 0
        let sideBob: Float = (d.headBob && !d.reduceMotion && moving) ? sin(bobPhase) * 0.018 * amount : 0
        cameraNode.simdPosition = SIMD3(sideBob, eyeHeight + bob, 0)
        let roll: Float = (d.headBob && !d.reduceMotion) ? -mv.x * 0.018 - sin(bobPhase) * 0.006 * amount : 0
        cameraNode.simdEulerAngles = SIMD3(pitch, 0, roll)
        // Footsteps on each step of the walk cycle.
        let step = Int(bobPhase / Float.pi)
        if step != lastStep {
            lastStep = step
            if moving && d.footsteps { Feedback.shared.play(.step, volume: 0.35 + 0.25 * amount) }
        }
        if let rig = rig {
            rig.root.isHidden = !d.showArms
            rig.update(dt: dt, now: time, move: moving ? amount : 0, bobPhase: bobPhase, lookDelta: lookDelta, pitch: pitch, reduceMotion: d.reduceMotion)
        }
        lookDelta = .zero
        if d.fieldOfView != lastFOV {
            lastFOV = d.fieldOfView
            cameraNode.camera?.fieldOfView = CGFloat(d.fieldOfView)
        }
    }

    func resolveCollisions(_ p: SIMD2<Float>) -> SIMD2<Float> {
        var q = p
        let r: Float = 0.28
        for _ in 0..<2 {
            for rect in playerRects {
                let cx = max(rect.minX, min(q.x, rect.maxX))
                let cz = max(rect.minZ, min(q.y, rect.maxZ))
                let d = q - SIMD2(cx, cz)
                let dist = simd_length(d)
                if dist >= r { continue }
                if dist > 1e-4 {
                    q = SIMD2(cx, cz) + d / dist * r
                } else {
                    let l = q.x - rect.minX, rr = rect.maxX - q.x, tt = q.y - rect.minZ, b = rect.maxZ - q.y
                    let m = min(l, rr, tt, b)
                    if m == l { q.x = rect.minX - r } else if m == rr { q.x = rect.maxX + r }
                    else if m == tt { q.y = rect.minZ - r } else { q.y = rect.maxZ + r }
                }
            }
        }
        return q
    }

    // MARK: Focus

    var cameraWorldPosition: SIMD3<Float> { cameraNode.simdWorldPosition }

    // MARK: Helpers

    func toast(_ text: String, _ style: ToastStyle = .info) { onToast?(text, style) }

    func refreshSigns() {
        for f in fixtures {
            f.refreshLabels(showLabels: display.showRowLabels, signScale: Float(display.signScale),
                            glow: scannerCategory != nil, glowCategory: scannerCategory)
        }
    }

    func refreshTags() {
        let show = display.showShelfTags
        for f in fixtures { for s in f.slots { s.refreshTag(visible: show) } }
    }

    func sparkle(at p: SIMD3<Float>, big: Bool) {
        guard display.sparkles, !display.reduceMotion else { return }
        let ps = SCNParticleSystem()
        ps.birthRate = big ? 900 : 350
        ps.emissionDuration = 0.08
        ps.loops = false
        ps.particleLifeSpan = big ? 0.9 : 0.55
        ps.particleVelocity = big ? 1.6 : 1.0
        ps.particleVelocityVariation = 0.6
        ps.spreadingAngle = 180
        ps.particleSize = 0.018
        ps.particleColor = UIColor(hex: big ? 0xFFD54A : 0x7CFFB2)
        ps.particleColorVariation = SCNVector4(0.1, 0.1, 0.1, 0)
        ps.acceleration = SCNVector3(0, -2.5, 0)
        ps.blendMode = .additive
        ps.isLightingEnabled = false
        let n = SCNNode()
        n.simdPosition = p
        n.addParticleSystem(ps)
        scene.rootNode.addChildNode(n)
        n.runAction(.sequence([.wait(duration: 1.6), .removeFromParentNode()]))
    }

    var remaining: Int {
        var n = floorItems.count + basket.count
        for f in fixtures { for s in f.slots { n += s.wrongCount } }
        return n
    }

    var progress: Double {
        guard total > 0 else { return 1 }
        return 1 - Double(remaining) / Double(total)
    }

    func timeString(_ t: Double? = nil) -> String {
        let v = Int(t ?? elapsed)
        return String(format: "%d:%02d", v / 60, v % 60)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
