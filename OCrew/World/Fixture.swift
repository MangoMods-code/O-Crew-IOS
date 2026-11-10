import SceneKit
import simd

/// One physical product unit somewhere in the store.
final class Item {
    let id: Int
    let product: String
    let expired: Bool
    var node: SCNNode?          // only while lying on the floor
    var floorPos = SIMD2<Float>(0, 0)
    var chunk = 0
    /// Tap box in the item's local space (before yaw): center and half size.
    var hitCenter = SIMD3<Float>(0, 0.1, 0)
    var hitHalf = SIMD3<Float>(0.1, 0.1, 0.1)
    var yaw: Float = 0
    var tipped = false

    init(id: Int, product: String, expired: Bool) {
        self.id = id
        self.product = product
        self.expired = expired
    }

    /// Items of the same product + freshness can share a shelf spot.
    var key: String { expired ? "x:" + product : product }
    var category: String { Catalog.product(product)?.category ?? "" }
}

@MainActor
final class Slot {
    let fixture: Int
    let index: Int
    let row: Int
    let node: SCNNode          // origin at the front-center of the shelf board, +z toward aisle
    let width: Float = 0.98
    let depth: Float
    let height: Float = 0.5
    var category: String?      // the row's label, nil for an unlabeled row
    var items: [Item] = []
    private var contentNode: SCNNode?
    let tagNode: SCNNode
    let hitNode: SCNNode
    var worldCenter: SIMD3<Float> = .zero
    /// World-space tap box (fixtures are axis-aligned).
    var boxMin = SIMD3<Float>(0, 0, 0)
    var boxMax = SIMD3<Float>(0, 0, 0)

    init(fixture: Int, index: Int, row: Int, depth: Float) {
        let w: Float = 0.98, h: Float = 0.5
        let root = SCNNode()

        let hitGeo = SCNBox(width: CGFloat(w - 0.02), height: CGFloat(h - 0.04), length: CGFloat(depth), chamferRadius: 0)
        hitGeo.firstMaterial = Models.invisible()
        let hit = SCNNode(geometry: hitGeo)
        hit.position = SCNVector3(0, (h - 0.04) / 2 + 0.01, -depth / 2)
        hit.name = "slot:\(fixture):\(index)"
        hit.isHidden = true   // hit-testable but never drawn
        root.addChildNode(hit)

        let tagGeo = SCNPlane(width: 0.3, height: 0.07)
        let m = SCNMaterial()
        m.lightingModel = .constant
        tagGeo.firstMaterial = m
        let tag = SCNNode(geometry: tagGeo)
        tag.position = SCNVector3(0, h - 0.06, -depth + 0.05)
        tag.categoryBitMask = Models.categoryNoHit
        tag.isHidden = true
        root.addChildNode(tag)

        self.fixture = fixture
        self.index = index
        self.row = row
        self.depth = depth
        self.node = root
        self.hitNode = hit
        self.tagNode = tag
    }

    var key: String? { items.first?.key }
    var product: String? { items.first?.product }
    var count: Int { items.count }

    /// Correct = labeled row matches the product's category, and nothing expired.
    var isCorrect: Bool {
        guard let first = items.first else { return true }
        return !first.expired && category != nil && first.category == category
    }

    var wrongCount: Int { isCorrect ? 0 : items.count }

    static func capacity(for p: Product, width: Float = 0.98, height: Float = 0.5) -> Int {
        let s = p.shape.size
        let cols = max(1, Int((width - 0.02) / (s.w + 0.012)))
        let stack = p.shape.stackable ? max(1, min(2, Int((height - 0.06) / (s.h + 0.004)))) : 1
        return min(cols * stack, 14)
    }

    var capacity: Int {
        guard let id = product, let p = Catalog.product(id) else { return 0 }
        return Slot.capacity(for: p)
    }

    var isFull: Bool { !items.isEmpty && items.count >= capacity }

    /// Rebuilds the stock in this spot as one mesh. Every item you place shows as a column
    /// running back into the shelf, so a full spot looks properly stocked.
    func rebuild(pop: Bool = false) {
        contentNode?.removeFromParentNode()
        contentNode = nil
        guard let first = items.first, let p = Catalog.product(first.product) else { return }
        let s = p.shape.size
        let cols = max(1, Int((width - 0.02) / (s.w + 0.012)))
        let stack = p.shape.stackable ? max(1, min(2, Int((height - 0.06) / (s.h + 0.004)))) : 1
        let cellW = (width - 0.02) / Float(cols)
        let zf = min(depth * 0.35, s.d / 2 + 0.05)          // front row, just behind the shelf edge
        let z = -zf
        let step = s.d + 0.012
        let deep = max(1, min(3, Int((depth - 0.02 - s.d / 2 - zf) / step) + 1))
        let batch = MeshBatcher()
        let tmpl = Models.template(p, expired: first.expired)
        for i in 0..<items.count {
            let col = (i / stack) % cols
            let layer = i % stack
            let x = -(width - 0.02) / 2 + (Float(col) + 0.5) * cellW
            let y = Float(layer) * (s.h + 0.004) + 0.002
            for r in 0..<deep {
                batch.add(tmpl, transform: Models.translate(x, y, z - Float(r) * step))
            }
        }
        guard let flat = batch.build() else { return }
        Models.setCategory(flat, Models.categoryNoHit)   // taps go to the slot's own box
        node.addChildNode(flat)
        contentNode = flat
        if pop {
            flat.scale = SCNVector3(1.035, 1.06, 1.035)
            let settle = SCNAction.scale(to: 1, duration: 0.12)
            settle.timingMode = .easeOut
            flat.runAction(settle)
        }
    }

    /// Where the next item will sit, in world space (for the fly-in animation).
    var nextItemWorldPosition: SIMD3<Float> {
        guard let first = items.first, let p = Catalog.product(first.product) else { return worldCenter }
        let s = p.shape.size
        let cols = max(1, Int((width - 0.02) / (s.w + 0.012)))
        let stack = p.shape.stackable ? max(1, min(2, Int((height - 0.06) / (s.h + 0.004)))) : 1
        let cellW = (width - 0.02) / Float(cols)
        let i = max(0, items.count - 1)
        let x = -(width - 0.02) / 2 + (Float((i / stack) % cols) + 0.5) * cellW
        let y = Float(i % stack) * (s.h + 0.004) + s.h / 2
        let w = node.simdConvertPosition(SIMD3(x, y, -min(depth * 0.35, s.d / 2 + 0.05)), to: nil)
        return w
    }

    func refreshTag(visible: Bool) {
        guard visible, let id = product, let p = Catalog.product(id) else {
            tagNode.isHidden = true
            return
        }
        tagNode.isHidden = false
        tagNode.geometry?.firstMaterial?.diffuse.contents = Models.shelfTagImage(p.name)
    }
}

@MainActor
final class Fixture {
    let index: Int
    let spec: FixtureSpec
    let node: SCNNode
    var slots: [Slot] = []
    var rowCategories: [String?] = [nil, nil, nil]
    /// Solid panels that block taps (back + ends), world-space boxes.
    var occluders: [(SIMD3<Float>, SIMD3<Float>)] = []
    private var rowLabelNodes: [SCNNode] = []
    private var rowLabelKeys: [String] = ["", "", ""]
    private let signNode = SCNNode()
    private var signKey = ""

    var kind: FixtureKind { spec.kind }

    init(index: Int, spec: FixtureSpec, shelfColor: UInt32, trim: UInt32) {
        self.index = index
        self.spec = spec
        node = SCNNode()
        node.name = "fixture:\(index)"
        node.simdPosition = SIMD3(spec.center.x, 0, spec.center.y)
        node.simdEulerAngles = SIMD3(0, atan2(spec.normal.x, spec.normal.y), 0)
        buildFrame(shelfColor: shelfColor, trim: trim)

        let usableDepth = spec.depth - 0.06
        var idx = 0
        for (row, y) in spec.levelHeights.enumerated() {
            for s in 0..<2 {
                let slot = Slot(fixture: index, index: idx, row: row, depth: usableDepth)
                let x = -spec.length / 2 + 0.5 + Float(s) * 1.0
                slot.node.position = SCNVector3(x, y, spec.depth / 2 - 0.01)
                node.addChildNode(slot.node)
                slots.append(slot)
                idx += 1
            }
            // Section label on the shelf edge
            let label = SCNNode(geometry: SCNPlane(width: CGFloat(spec.length - 0.1), height: 0.06))
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.mipFilter = .linear
            label.geometry?.firstMaterial = m
            label.position = SCNVector3(0, y - 0.03, spec.depth / 2 + 0.008)
            label.categoryBitMask = Models.categoryNoHit
            label.castsShadow = false
            node.addChildNode(label)
            rowLabelNodes.append(label)
        }
        signNode.categoryBitMask = Models.categoryNoHit
        signNode.position = SCNVector3(0, spec.height + 0.42, spec.depth / 2 - 0.1)
        node.addChildNode(signNode)

        let yaw = atan2(spec.normal.x, spec.normal.y)
        let right = SIMD2<Float>(cos(yaw), -sin(yaw))
        // World boxes: rotate a local (x along shelf, z toward aisle) box into world space.
        func worldBox(_ c: SIMD3<Float>, _ half: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
            let p = spec.center + right * c.x + spec.normal * c.z
            let alongX = abs(right.x) > 0.5
            let hx = alongX ? half.x : half.z, hz = alongX ? half.z : half.x
            return (SIMD3(p.x - hx, c.y - half.y, p.y - hz), SIMD3(p.x + hx, c.y + half.y, p.y + hz))
        }
        for slot in slots {
            let base = spec.center + right * slot.node.position.x
            let front = base + spec.normal * (spec.depth / 2 - 0.2)
            slot.worldCenter = SIMD3(front.x, slot.node.position.y + 0.2, front.y)
            let sd = slot.depth
            let c = SIMD3<Float>(slot.node.position.x, slot.node.position.y + 0.24, spec.depth / 2 - 0.01 - sd / 2)
            let b = worldBox(c, SIMD3(0.47, 0.23, sd / 2))
            slot.boxMin = b.0
            slot.boxMax = b.1
        }
        let H = spec.height, L = spec.length, D = spec.depth
        occluders.append(worldBox(SIMD3(0, H / 2, -D / 2 + 0.03), SIMD3(L / 2, H / 2, 0.03)))
        occluders.append(worldBox(SIMD3(-L / 2 + 0.02, H / 2, 0), SIMD3(0.02, H / 2, D / 2)))
        occluders.append(worldBox(SIMD3(L / 2 - 0.02, H / 2, 0), SIMD3(0.02, H / 2, D / 2)))
        occluders.append(worldBox(SIMD3(0, 0.05, 0), SIMD3(L / 2, 0.05, D / 2)))
    }

    func setRows(_ cats: [String?], showLabels: Bool, signScale: Float) {
        rowCategories = cats
        for slot in slots { slot.category = cats[slot.row] }
        refreshLabels(showLabels: showLabels, signScale: signScale, glow: false)
    }

    /// Spots that are full of the right stock.
    var doneSlots: Int { slots.filter { $0.isFull && $0.isCorrect }.count }
    var isDone: Bool { doneSlots == slots.count }

    func refreshLabels(showLabels: Bool, signScale: Float, glow: Bool, glowCategory: String? = nil) {
        for (i, n) in rowLabelNodes.enumerated() {
            let cat = rowCategories[i]
            n.isHidden = !showLabels
            let lit = glow && cat != nil && cat == glowCategory
            let key = (cat ?? "-") + (lit ? "|1" : "|0")
            if key != rowLabelKeys[i] {
                rowLabelKeys[i] = key
                n.geometry?.firstMaterial?.diffuse.contents = Models.rowLabelImage(cat, lit: lit)
            }
        }
        // Hanging sign: the sections on this unit, with how much of it is stocked.
        var seen: [String] = []
        for c in rowCategories.compactMap({ $0 }) where !seen.contains(c) { seen.append(c) }
        guard !seen.isEmpty else { signNode.childNodes.forEach { $0.removeFromParentNode() }; signKey = ""; return }
        let lit = glow && glowCategory != nil && seen.contains(glowCategory!)
        let done = doneSlots
        let key = "\(seen.joined(separator: ","))|\(done)|\(lit)|\(signScale)"
        guard key != signKey else { return }
        signKey = key
        signNode.childNodes.forEach { $0.removeFromParentNode() }
        let w = 1.55 * signScale, h = w * 150 / 512
        let plane = SCNPlane(width: CGFloat(w), height: CGFloat(h))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.diffuse.mipFilter = .linear
        m.diffuse.contents = Models.sectionSign(seen, done: done, total: slots.count, lit: lit)
        plane.firstMaterial = m
        let n = SCNNode(geometry: plane)
        n.categoryBitMask = Models.categoryNoHit
        n.castsShadow = false
        signNode.addChildNode(n)
        for x in [-w / 2 + 0.12, w / 2 - 0.12] {
            let wire = Models.box(0.012, 0.5, 0.012, 0x8A8F96)
            wire.categoryBitMask = Models.categoryNoHit
            wire.castsShadow = false
            wire.position = SCNVector3(x, h / 2 + 0.25, 0)
            signNode.addChildNode(wire)
        }
    }

    private func buildFrame(shelfColor: UInt32, trim: UInt32) {
        let L = spec.length, D = spec.depth, H = spec.height
        let b = MeshBuilder()
        switch spec.kind {
        case .shelf:
            let dark = Mats.solid(Mats.shade(shelfColor, 0.5), gloss: 0.2)
            let boardHex = Mats.mix(shelfColor, 0xFFFFFF, 0.6)
            let board = Mats.solid(boardHex, gloss: 0.25)
            let side = Mats.solid(Mats.mix(shelfColor, 0xFFFFFF, 0.35), gloss: 0.15)
            let back = Mats.tiled("peg\(shelfColor)") { Mats.pegboard(Mats.mix(shelfColor, 0xFFFFFF, 0.72)) }
            let rail = Mats.solid(trim, gloss: 0.25)
            b.box(0, 0.05, 0, L, 0.1, D, dark)                                           // kick plate
            b.box(0, H / 2 + 0.05, -D / 2 + 0.015, L - 0.04, H - 0.1, 0.03, back, uvScale: 5)   // pegboard back
            for x in [-L / 2 + 0.02, L / 2 - 0.02] { b.box(x, H / 2, 0, 0.04, H, D, side) }     // end panels
            b.box(0, H / 2 + 0.03, -0.02, 0.02, H - 0.14, D - 0.08, side)                // divider
            for x in [-L / 2 + 0.05, 0, L / 2 - 0.05] { b.box(x, H / 2, -D / 2 + 0.045, 0.05, H, 0.03, dark) }   // uprights
            for (i, y) in spec.levelHeights.enumerated() {
                if i > 0 { b.box(0, y - 0.015, 0.0, L - 0.08, 0.03, D - 0.04, board) }   // shelf board
                b.box(0, y - 0.03, D / 2 - 0.006, L - 0.08, 0.064, 0.012, rail)          // price rail
            }
            b.box(0, H - 0.02, 0, L, 0.04, D, dark)                                      // top
            b.box(0, H + 0.06, D / 2 - 0.02, L, 0.12, 0.03, rail)                        // header strip
        case .fridge, .freezer:
            let fridge = spec.kind == .fridge
            let shell = Mats.solid(fridge ? 0x2A3038 : 0xE4EAEE, gloss: 0.35)
            let inner = Mats.glow(fridge ? 0xF4F9FC : 0xEAF6FF)
            let wire = Mats.solid(0xC5CED6, gloss: 0.4)
            let accent = Mats.solid(fridge ? 0x3E8EDE : 0x66C7F4, gloss: 0.3)
            let grille = Mats.solid(0x14181D)
            let metal = Mats.solid(0xB9C0C7, gloss: 0.6)
            b.box(0, 0.07, 0, L, 0.14, D, shell)                                         // base
            b.box(0, 0.07, D / 2 + 0.002, L - 0.16, 0.06, 0.004, grille)                 // vent grille
            b.box(0, H / 2 + 0.07, -D / 2 + 0.03, L - 0.08, H - 0.14, 0.02, inner)       // lit back wall
            for x in [-L / 2 + 0.025, L / 2 - 0.025] { b.box(x, H / 2, 0, 0.05, H, D, shell) }
            b.box(0, H - 0.07, 0, L, 0.14, D, shell)                                     // top box
            b.box(0, H - 0.07, D / 2 + 0.002, L - 0.1, 0.07, 0.004, accent)              // brand strip
            b.box(0, H - 0.155, D / 2 - 0.06, L - 0.12, 0.02, 0.04, Mats.glow(0xFFFFFF)) // light bar
            b.box(0, H / 2, D / 2 - 0.025, 0.04, H - 0.28, 0.05, shell)                  // door mullion
            for (i, y) in spec.levelHeights.enumerated() {
                if i > 0 { b.box(0, y - 0.01, -0.01, L - 0.1, 0.014, D - 0.1, wire) }
                b.box(0, y - 0.03, D / 2 - 0.05, L - 0.1, 0.06, 0.01, wire)
            }
            // Door frames + handles (the glass itself is a separate see-through node)
            for sx in [Float(-1), Float(1)] {
                let cx = sx * L / 4
                let w = L / 2 - 0.05
                b.box(cx, H - 0.165, D / 2 + 0.02, w, 0.035, 0.02, shell)
                b.box(cx, 0.16, D / 2 + 0.02, w, 0.035, 0.02, shell)
                b.box(cx - w / 2 + 0.015, H / 2, D / 2 + 0.02, 0.03, H - 0.3, 0.02, shell)
                b.box(cx + w / 2 - 0.015, H / 2, D / 2 + 0.02, 0.03, H - 0.3, 0.02, shell)
                b.box(cx - sx * (w / 2 - 0.1), H / 2, D / 2 + 0.05, 0.022, 0.55, 0.025, metal)
            }
        }
        if let frame = b.build() {
            Models.setCategory(frame, Models.categoryNoHit)
            node.addChildNode(frame)
        }
        if spec.kind != .shelf {
            // Glass: faint tint with a couple of reflection streaks.
            let glass = SCNNode(geometry: SCNPlane(width: CGFloat(L - 0.1), height: CGFloat(H - 0.32)))
            let m = SCNMaterial()
            m.diffuse.contents = Models.glassImage(tint: spec.kind == .fridge ? 0xBFE6FF : 0xE6F6FF)
            m.lightingModel = .constant
            m.isDoubleSided = true
            m.writesToDepthBuffer = false
            m.blendMode = .alpha
            glass.geometry?.firstMaterial = m
            glass.categoryBitMask = Models.categoryNoHit
            glass.castsShadow = false
            glass.renderingOrder = 20
            glass.position = SCNVector3(0, H / 2, D / 2 + 0.022)
            node.addChildNode(glass)
        }
    }
}
