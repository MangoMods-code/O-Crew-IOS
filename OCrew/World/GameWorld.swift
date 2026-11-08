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

    // MARK: Items
    var items: [Int: Item] = [:]
    var floorItems: [Int: Item] = [:]
    var basket: [Item] = []
    var selectedKey: String?
    var binned = 0
    var total = 0
    var nextItemID = 1
    var chunks: [Int: FloorChunk] = [:]
    var chunksDirty = false
    var lastFOV: Double = 0
    var rig: FirstPersonRig?
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

    // MARK: Callbacks
    var onToast: ((String, ToastStyle) -> Void)?
    var onComplete: ((LevelResult) -> Void)?
    var onBasketChanged: (() -> Void)?

    var display: DisplaySettings { SettingsStore.shared.display }
    var game: GameSettings { SettingsStore.shared.game }
    var capacity: Int { max(3, Int(game.basketCapacity.rounded())) }
    var par: Double { (45 + Double(total) * 2.5) * game.parTimeScale }

    // MARK: Init

    init(level: OrgLevel, save: LevelSave?) {
        self.level = level

        // Plan shelf rows: each category gets enough rows for its products.
        var groups: [(kind: FixtureKind, cat: String, count: Int)] = []
        for id in level.products {
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
        let extra = Float(level.products.count / 6) + (level.stage == 3 ? 1 : 0)
        layout = StoreLayout.fit(cold: cold, shelves: max(1, units(.shelf)), minWidth: 9 + extra, minDepth: 11 + extra)
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

        // Label the rows
        var queues = rowQueues
        for f in fixtures {
            var cats: [String?] = []
            for _ in 0..<3 {
                if var q = queues[f.kind], !q.isEmpty {
                    cats.append(q.removeFirst())
                    queues[f.kind] = q
                } else {
                    cats.append(nil)
                }
            }
            f.setRows(cats, showLabels: display.showRowLabels, signScale: Float(display.signScale))
        }

        if let s = save, s.fixtureCount == fixtures.count, restore(s) {
            // restored
        } else {
            generateMess()
        }
        tutorialActive = level.index == 0 && game.showTutorial && !ProgressStore.shared.data.seenTutorial && save == nil
        rebuildChunks()
        updateBasketVisual()
    }

    // MARK: Mess generation

    private func generateMess() {
        var list: [Item] = []
        for id in level.products {
            guard let p = Catalog.product(id) else { continue }
            let cap = Slot.capacity(for: p) * level.slotsPerProduct
            let n = max(2, min(cap, Int((Double(cap) * level.fill * game.messSize).rounded())))
            for _ in 0..<n { list.append(makeItem(id, expired: false)) }
        }
        if game.expiredItems && level.expired > 0 {
            for _ in 0..<level.expired {
                if let id = level.products.randomElement() { list.append(makeItem(id, expired: true)) }
            }
        }
        total = list.count
        list.shuffle()

        // Some products start on the wrong shelves.
        if game.misplacedItems && level.misplaced > 0 {
            let k = Int((Double(level.products.count) * level.misplaced).rounded())
            for id in level.products.shuffled().prefix(k) {
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
            c.dirty = true
            chunksDirty = true
        }
    }

    func chunkKey(_ p: SIMD2<Float>) -> Int {
        Int(floor(p.x / 4)) * 1000 + Int(floor(p.y / 4))
    }

    /// Rebuilds the merged meshes of any chunk that changed.
    func rebuildChunks() {
        guard chunksDirty else { return }
        chunksDirty = false
        for c in chunks.values where c.dirty {
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
                var m = Models.translate(it.floorPos.x, 0, it.floorPos.y) * Models.rotate(it.yaw, SIMD3(0, 1, 0))
                if it.tipped {
                    m = m * Models.translate(0, p.shape.size.w / 2, 0) * Models.rotate(Float.pi / 2, SIMD3(0, 0, 1))
                }
                batch.add(Models.template(p, expired: it.expired), transform: m)
                // Contact shadow footprint
                let sz = p.shape.size
                let fx = (it.tipped ? sz.h : sz.w) + 0.08
                let fz = sz.d + 0.08
                let center = it.tipped ? SIMD3<Float>(-sz.h / 2, 0, 0) : SIMD3<Float>(0, 0, 0)
                var sm = Models.translate(it.floorPos.x, 0.003, it.floorPos.y) * Models.rotate(it.yaw, SIMD3(0, 1, 0))
                sm = sm * Models.translate(center.x, 0, 0)
                var scale = matrix_identity_float4x4
                scale.columns.0.x = fx * 1.25
                scale.columns.2.z = fz * 1.25
                shadows.add(ContactShadow.mesh, transform: sm * scale)
            }
            if let sh = shadows.build() {
                sh.renderingOrder = 5
                Models.setCategory(sh, Models.categoryNoHit)
                scene.rootNode.addChildNode(sh)
                c.shadow = sh
            }
            let flat: SCNNode
            if let merged = batch.build() {
                flat = merged
            } else {
                // Fallback: individual models (slower, but always visible).
                let container = SCNNode()
                for id in c.items {
                    guard let it = floorItems[id], let p = Catalog.product(it.product) else { continue }
                    let holder = SCNNode()
                    holder.simdPosition = SIMD3(it.floorPos.x, 0, it.floorPos.y)
                    holder.simdEulerAngles = SIMD3(0, it.yaw, 0)
                    let m = Models.productNode(p, expired: it.expired)
                    if it.tipped {
                        m.eulerAngles.z = Float.pi / 2
                        m.position.y = p.shape.size.w / 2
                    }
                    holder.addChildNode(m)
                    container.addChildNode(holder)
                }
                flat = container
            }
            Models.setCategory(flat, Models.categoryNoHit)
            scene.rootNode.addChildNode(flat)
            c.visual = flat
        }
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
                for it in s.items { saves.append(ItemSave(product: it.product, expired: it.expired, loc: 2, f: f.index, s: s.index)) }
            }
        }
        ProgressStore.shared.store(LevelSave(levelID: level.id, elapsed: elapsed, mistakes: mistakes, binned: binned,
                                             total: total, fixtureCount: fixtures.count, items: saves))
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
        return true
    }

    // MARK: Scene

    private func buildScene() {
        let W = layout.width, D = layout.depth
        let root = SCNNode()   // static geometry, merged into one mesh below
        let theme = level.theme

        let floor = SCNPlane(width: CGFloat(W), height: CGFloat(D))
        let fm = Models.imageMat(Models.checkerImage(theme.floor, theme.floorAlt, grout: theme.floorAlt &- 0x101010))
        fm.diffuse.wrapS = .repeat
        fm.diffuse.wrapT = .repeat
        fm.diffuse.contentsTransform = SCNMatrix4MakeScale(W / 1.2, D / 1.2, 1)
        floor.firstMaterial = fm
        let floorNode = SCNNode(geometry: floor)
        floorNode.eulerAngles.x = -Float.pi / 2
        floorNode.position = SCNVector3(W / 2, 0, D / 2)
        floorNode.categoryBitMask = Models.categoryNoHit
        root.addChildNode(floorNode)

        let H: Float = 3.2, t = layout.wallThickness
        func wall(_ x0: Float, _ z0: Float, _ x1: Float, _ z1: Float, _ h: Float, _ y: Float) {
            let n = Models.box(max(0.01, x1 - x0), h, max(0.01, z1 - z0), theme.wall)
            n.position = SCNVector3((x0 + x1) / 2, y + h / 2, (z0 + z1) / 2)
            root.addChildNode(n)
        }
        wall(-t, -t, W + t, 0, H, 0)
        wall(-t, 0, 0, D + t, H, 0)
        wall(W, 0, W + t, D + t, H, 0)
        wall(-t, D, layout.doorMinX, D + t, H, 0)
        wall(layout.doorMaxX, D, W + t, D + t, H, 0)
        wall(layout.doorMinX, D, layout.doorMaxX, D + t, H - 2.4, 2.4)
        // Closed glass doors
        let glass = SCNNode(geometry: SCNBox(width: CGFloat(layout.doorMaxX - layout.doorMinX), height: 2.4, length: 0.05, chamferRadius: 0))
        glass.geometry?.firstMaterial = Models.freshMat(0xBFE0F5, alpha: 0.35)
        glass.position = SCNVector3((layout.doorMinX + layout.doorMaxX) / 2, 1.2, D + t / 2)
        glass.categoryBitMask = Models.categoryNoHit
        root.addChildNode(glass)
        let closed = Models.billboardText("SORRY, WE'RE CLOSED", color: .white, bg: UIColor(hex: 0xB03A2E), width: 1.4, height: 0.24, fontSize: 52)
        closed.constraints = nil
        closed.eulerAngles.y = Float.pi
        closed.position = SCNVector3((layout.doorMinX + layout.doorMaxX) / 2, 1.5, D - 0.02)
        closed.geometry?.firstMaterial?.readsFromDepthBuffer = true
        scene.rootNode.addChildNode(closed)

        func trim(_ x0: Float, _ z0: Float, _ x1: Float, _ z1: Float, y: Float, h: Float) {
            let n = Models.box(max(0.01, x1 - x0), h, max(0.01, z1 - z0), theme.trim)
            n.position = SCNVector3((x0 + x1) / 2, y, (z0 + z1) / 2)
            n.categoryBitMask = Models.categoryNoHit
            root.addChildNode(n)
        }
        for y in [Float(0.08), Float(2.6)] {
            let h: Float = y < 1 ? 0.16 : 0.22
            trim(0, 0, W, 0.02, y: y, h: h)
            trim(0, 0, 0.02, D, y: y, h: h)
            trim(W - 0.02, 0, W, D, y: y, h: h)
            trim(0, D - 0.02, layout.doorMinX, D, y: y, h: h)
            trim(layout.doorMaxX, D - 0.02, W, D, y: y, h: h)
        }
        // Store name over the back wall
        let name = Models.billboardText(theme.name.uppercased(), color: .white, bg: UIColor(hex: theme.trim), width: 3.6, height: 0.5, fontSize: 110)
        name.constraints = nil
        name.position = SCNVector3(W / 2, 2.95, 0.03)
        name.geometry?.firstMaterial?.readsFromDepthBuffer = true
        scene.rootNode.addChildNode(name)

        let ceil = SCNNode(geometry: SCNPlane(width: CGFloat(W), height: CGFloat(D)))
        ceil.geometry?.firstMaterial = Models.mat(0xF2F2EE)
        ceil.eulerAngles.x = Float.pi / 2
        ceil.position = SCNVector3(W / 2, H, D / 2)
        ceil.categoryBitMask = Models.categoryNoHit
        root.addChildNode(ceil)
        var lx: Float = 1.5
        while lx < W - 1 {
            var lz: Float = 1.5
            while lz < D - 1 {
                let panel = SCNNode(geometry: SCNPlane(width: 1.2, height: 0.5))
                panel.geometry?.firstMaterial = Models.emissive(0xFFFDF2)
                panel.eulerAngles.x = Float.pi / 2
                panel.position = SCNVector3(lx, H - 0.01, lz)
                panel.categoryBitMask = Models.categoryNoHit
                root.addChildNode(panel)
                lz += 3
            }
            lx += 3
        }

        let env = Models.merged(root)
        Models.setCategory(env, Models.categoryNoHit)
        scene.rootNode.addChildNode(env)
        let worldRoot = scene.rootNode

        let ambient = SCNNode(); ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 540
        ambient.light!.color = UIColor(hex: 0xFFF8EE)
        worldRoot.addChildNode(ambient)
        let sun = SCNNode(); sun.light = SCNLight()
        sun.light!.type = .directional
        sun.light!.intensity = 600
        sun.eulerAngles = SCNVector3(Float(-1.05), Float(0.55), Float(0))
        worldRoot.addChildNode(sun)
        let fill = SCNNode(); fill.light = SCNLight()
        fill.light!.type = .directional
        fill.light!.intensity = 220
        fill.eulerAngles = SCNVector3(Float(-0.6), Float.pi + 0.4, Float(0))
        worldRoot.addChildNode(fill)

        for (i, spec) in layout.fixtures.enumerated() {
            let f = Fixture(index: i, spec: spec, shelfColor: theme.shelfColor)
            fixtures.append(f)
            worldRoot.addChildNode(f.node)
        }

        // Trash bin for expired stock
        let bin = SCNNode()
        bin.name = "bin"
        let can = SCNNode(geometry: SCNCylinder(radius: 0.3, height: 0.85))
        can.geometry?.firstMaterial = Models.mat(0x566573)
        can.position.y = 0.425
        bin.addChildNode(can)
        let lid = SCNNode(geometry: SCNCylinder(radius: 0.32, height: 0.05))
        lid.geometry?.firstMaterial = Models.mat(0xC0392B)
        lid.position.y = 0.87
        bin.addChildNode(lid)
        let binSign = Models.billboardText("EXPIRED", color: .white, bg: UIColor(hex: 0xC0392B), width: 0.7, height: 0.18, fontSize: 60)
        binSign.position.y = 1.25
        binSign.geometry?.firstMaterial?.readsFromDepthBuffer = true
        bin.addChildNode(binSign)
        bin.position = SCNVector3(layout.bin.center.x, 0, layout.bin.center.y)
        worldRoot.addChildNode(bin)

        // Player + held basket
        playerNode.simdPosition = SIMD3(playerPos.x, 0, playerPos.y)
        let cam = SCNCamera()
        cam.projectionDirection = .horizontal
        cam.fieldOfView = CGFloat(display.fieldOfView)
        cam.zNear = 0.05
        cam.zFar = 80
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, eyeHeight, 0)
        playerNode.addChildNode(cameraNode)
        let arms = FirstPersonRig(sleeve: theme.trim, skin: 0xE0AC69)
        arms.basketHolder.addChildNode(basketNode)
        basketNode.scale = SCNVector3(0.8, 0.8, 0.8)
        cameraNode.addChildNode(arms.root)
        rig = arms
        worldRoot.addChildNode(playerNode)
        worldRoot.addChildNode(highlightNode)
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
        rebuildChunks()
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
        playerPos = resolveCollisions(playerPos + (forward * mv.y + right * mv.x) * speed * dt)
        playerNode.simdPosition = SIMD3(playerPos.x, 0, playerPos.y)

        let moving = simd_length(mv) > 0.08
        if moving { bobPhase += dt * speed * 3.4 }
        let amount = min(1, simd_length(mv))
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
            rig.update(dt: dt, now: time, move: moving ? amount : 0, bobPhase: bobPhase, lookDelta: lookDelta, reduceMotion: d.reduceMotion)
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
