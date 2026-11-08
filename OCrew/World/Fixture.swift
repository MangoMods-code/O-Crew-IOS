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

    func rebuild() {
        contentNode?.removeFromParentNode()
        contentNode = nil
        guard let first = items.first, let p = Catalog.product(first.product) else { return }
        let s = p.shape.size
        let cols = max(1, Int((width - 0.02) / (s.w + 0.012)))
        let stack = p.shape.stackable ? max(1, min(2, Int((height - 0.06) / (s.h + 0.004)))) : 1
        let cellW = (width - 0.02) / Float(cols)
        let z = -min(depth * 0.35, s.d / 2 + 0.06)   // a neat front-facing row
        let container = SCNNode()
        for i in 0..<items.count {
            let col = (i / stack) % cols
            let layer = i % stack
            let x = -(width - 0.02) / 2 + (Float(col) + 0.5) * cellW
            let unit = Models.productNode(p, expired: first.expired)
            unit.position = SCNVector3(x, Float(layer) * (s.h + 0.004) + 0.002, z)
            container.addChildNode(unit)
        }
        let flat = Models.merged(container)
        node.addChildNode(flat)
        contentNode = flat
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
    private var rowLabelNodes: [SCNNode] = []
    private let signNode = SCNNode()

    var kind: FixtureKind { spec.kind }

    init(index: Int, spec: FixtureSpec, shelfColor: UInt32) {
        self.index = index
        self.spec = spec
        node = SCNNode()
        node.name = "fixture:\(index)"
        node.simdPosition = SIMD3(spec.center.x, 0, spec.center.y)
        node.simdEulerAngles = SIMD3(0, atan2(spec.normal.x, spec.normal.y), 0)
        buildFrame(shelfColor: shelfColor)

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
            // Row label strip on the shelf lip
            let label = SCNNode(geometry: SCNPlane(width: CGFloat(spec.length - 0.1), height: 0.055))
            let m = SCNMaterial()
            m.lightingModel = .constant
            label.geometry?.firstMaterial = m
            label.position = SCNVector3(0, y - 0.03, spec.depth / 2 + 0.004)
            label.categoryBitMask = Models.categoryNoHit
            node.addChildNode(label)
            rowLabelNodes.append(label)
        }
        signNode.categoryBitMask = Models.categoryNoHit
        signNode.position = SCNVector3(0, spec.height + 0.32, spec.depth / 2 - 0.1)
        node.addChildNode(signNode)

        let yaw = atan2(spec.normal.x, spec.normal.y)
        let right = SIMD2<Float>(cos(yaw), -sin(yaw))
        for slot in slots {
            let base = spec.center + right * slot.node.position.x
            let front = base + spec.normal * (spec.depth / 2 - 0.2)
            slot.worldCenter = SIMD3(front.x, slot.node.position.y + 0.2, front.y)
        }
    }

    func setRows(_ cats: [String?], showLabels: Bool, signScale: Float) {
        rowCategories = cats
        for slot in slots { slot.category = cats[slot.row] }
        refreshLabels(showLabels: showLabels, signScale: signScale, glow: false)
    }

    func refreshLabels(showLabels: Bool, signScale: Float, glow: Bool, glowCategory: String? = nil) {
        for (i, n) in rowLabelNodes.enumerated() {
            let cat = rowCategories[i]
            n.isHidden = !showLabels
            let lit = glow && cat != nil && cat == glowCategory
            n.geometry?.firstMaterial?.diffuse.contents = Models.rowLabelImage(cat ?? "—", lit: lit)
        }
        // Top sign: unique categories on this unit
        signNode.childNodes.forEach { $0.removeFromParentNode() }
        var seen: [String] = []
        for c in rowCategories.compactMap({ $0 }) where !seen.contains(c) { seen.append(c) }
        guard !seen.isEmpty else { return }
        let lit = glow && glowCategory != nil && seen.contains(glowCategory!)
        let text = seen.joined(separator: " · ").uppercased()
        let w = min(spec.length, Float(max(0.9, Double(text.count) * 0.085))) * signScale
        let plane = SCNPlane(width: CGFloat(w), height: CGFloat(0.3 * signScale))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.diffuse.contents = Models.signImage(text, lit: lit)
        plane.firstMaterial = m
        let n = SCNNode(geometry: plane)
        n.categoryBitMask = Models.categoryNoHit
        signNode.addChildNode(n)
        let hanger = Models.box(0.02, 0.3, 0.02, 0x555555)
        hanger.categoryBitMask = Models.categoryNoHit
        for x in [-w / 2 + 0.1, w / 2 - 0.1] {
            let h = hanger.clone()
            h.position = SCNVector3(x, 0.15 * signScale + 0.12, 0)
            signNode.addChildNode(h)
        }
    }

    private func buildFrame(shelfColor: UInt32) {
        let L = spec.length, D = spec.depth, H = spec.height
        let isCold = spec.kind != .shelf
        let frameColor: UInt32 = isCold ? (spec.kind == .fridge ? 0x3B4651 : 0xE3EEF4) : shelfColor
        let backColor: UInt32 = isCold ? 0xF4F8FA : shelfColor

        let frame = SCNNode()
        func add(_ n: SCNNode, _ x: Float, _ y: Float, _ z: Float) {
            n.position = SCNVector3(x, y, z)
            frame.addChildNode(n)
        }
        add(Models.box(L, 0.1, D, frameColor), 0, 0.05, 0)
        add(Models.box(L, H, 0.04, backColor), 0, H / 2, -D / 2 + 0.02)
        add(Models.box(0.04, H, D, frameColor), -L / 2 + 0.02, H / 2, 0)
        add(Models.box(0.04, H, D, frameColor), L / 2 - 0.02, H / 2, 0)
        add(Models.box(L, 0.05, D, frameColor), 0, H - 0.025, 0)
        add(Models.box(0.04, H - 0.1, D - 0.04, frameColor), 0, H / 2, 0)
        for y in spec.levelHeights.dropFirst() {
            add(Models.box(L - 0.06, 0.025, D - 0.04, isCold ? 0xC9D6DF : shelfColor), 0, y - 0.0125, 0.0)
        }
        if isCold {
            let strip = SCNNode(geometry: SCNBox(width: CGFloat(L - 0.1), height: 0.03, length: 0.03, chamferRadius: 0))
            strip.geometry?.firstMaterial = Models.emissive(0xE8F8FF)
            add(strip, 0, H - 0.08, D / 2 - 0.05)
        }
        // One merged mesh for the whole frame.
        node.addChildNode(Models.merged(frame))
        if isCold {
            // Glass stays separate so it never blocks taps on the shelves behind it.
            let glass = SCNNode(geometry: SCNBox(width: CGFloat(L - 0.06), height: CGFloat(H - 0.16), length: 0.015, chamferRadius: 0))
            glass.geometry?.firstMaterial = Models.freshMat(spec.kind == .fridge ? 0xBFE6FF : 0xDDF3FF, alpha: 0.14)
            glass.categoryBitMask = Models.categoryNoHit
            glass.position = SCNVector3(0, H / 2 + 0.03, D / 2 + 0.02)
            node.addChildNode(glass)
        }
    }
}
