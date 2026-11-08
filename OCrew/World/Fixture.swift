import SceneKit
import simd

@MainActor
final class Slot {
    let fixture: Int
    let index: Int
    let node: SCNNode          // origin at the front-center of the shelf board, +z toward aisle
    let width: Float = 0.98
    let depth: Float
    let height: Float = 0.5
    var product: String?
    var count: Int = 0
    private var contentNode: SCNNode?
    let tagNode: SCNNode
    let hitNode: SCNNode
    /// World position (x,z) where a shopper stands to reach this slot.
    var standPoint: SIMD2<Float> = .zero
    var worldCenter: SIMD3<Float> = .zero

    init(fixture: Int, index: Int, depth: Float) {
        let w: Float = 0.98, h: Float = 0.5
        let root = SCNNode()

        let hitGeo = SCNBox(width: CGFloat(w - 0.02), height: CGFloat(h - 0.04), length: CGFloat(depth), chamferRadius: 0)
        hitGeo.firstMaterial = Models.invisible()
        let hit = SCNNode(geometry: hitGeo)
        hit.position = SCNVector3(0, (h - 0.04) / 2 + 0.01, -depth / 2)
        hit.name = "slot:\(fixture):\(index)"
        root.addChildNode(hit)

        let tagGeo = SCNPlane(width: 0.22, height: 0.076)
        let m = SCNMaterial()
        m.lightingModel = .constant
        tagGeo.firstMaterial = m
        let tag = SCNNode(geometry: tagGeo)
        tag.position = SCNVector3(0, -0.04, 0.018)
        tag.categoryBitMask = Models.categoryNoHit
        tag.isHidden = true
        root.addChildNode(tag)

        self.fixture = fixture
        self.index = index
        self.depth = depth
        self.node = root
        self.hitNode = hit
        self.tagNode = tag
    }

    func capacity(for p: Product) -> Int {
        let s = p.shape.size
        let cols = max(1, Int((width - 0.02) / (s.w + 0.012)))
        let rows = max(1, Int((depth - 0.04) / (s.d + 0.012)))
        let stack = p.shape.stackable ? max(1, min(4, Int((height - 0.06) / (s.h + 0.004)))) : 1
        return min(cols * rows * stack, 30)
    }

    var capacity: Int {
        guard let id = product, let p = Catalog.product(id) else { return 0 }
        return capacity(for: p)
    }

    var isFull: Bool { product != nil && count >= capacity }

    /// Rebuilds the product meshes (merged into one node for performance).
    func rebuild() {
        contentNode?.removeFromParentNode()
        contentNode = nil
        guard let id = product, let p = Catalog.product(id), count > 0 else { return }
        let s = p.shape.size
        let cols = max(1, Int((width - 0.02) / (s.w + 0.012)))
        let rows = max(1, Int((depth - 0.04) / (s.d + 0.012)))
        let stack = p.shape.stackable ? max(1, min(4, Int((height - 0.06) / (s.h + 0.004)))) : 1
        let cellW = (width - 0.02) / Float(cols)
        let cellD = (depth - 0.04) / Float(rows)
        let container = SCNNode()
        for i in 0..<min(count, 30) {
            let layer = i % stack
            let col = (i / stack) % cols
            let row = i / (stack * cols)          // row 0 = back of shelf
            let x = -(width - 0.02) / 2 + (Float(col) + 0.5) * cellW
            let z = -depth + 0.02 + (Float(row) + 0.5) * cellD
            let unit = Models.productNode(p)
            unit.position = SCNVector3(x, Float(layer) * (s.h + 0.004) + 0.002, z)
            container.addChildNode(unit)
        }
        let flat = container.flattenedClone()
        node.addChildNode(flat)
        contentNode = flat
    }

    func refreshTag(price: Double?, symbol: String, visible: Bool) {
        guard visible, let id = product, let p = Catalog.product(id), let price = price else {
            tagNode.isHidden = true
            return
        }
        tagNode.isHidden = false
        tagNode.geometry?.firstMaterial?.diffuse.contents =
            Models.priceTagImage(name: p.name, price: formatMoney(price, symbol: symbol))
    }
}

@MainActor
final class Fixture {
    let index: Int
    let spec: FixtureSpec
    let node: SCNNode
    var slots: [Slot] = []

    var kind: FixtureKind { spec.kind }

    init(index: Int, spec: FixtureSpec, shelfColor: UInt32) {
        self.index = index
        self.spec = spec
        node = SCNNode()
        node.name = "fixture:\(index)"
        node.simdPosition = SIMD3(spec.center.x, 0, spec.center.y)
        node.simdEulerAngles = SIMD3(0, atan2(spec.normal.x, spec.normal.y), 0)
        buildFrame(shelfColor: shelfColor)

        let levels = spec.levelHeights
        let usableDepth = spec.depth - 0.06
        var idx = 0
        for y in levels {
            for s in 0..<2 {
                let slot = Slot(fixture: index, index: idx, depth: usableDepth)
                let x = -spec.length / 2 + 0.5 + Float(s) * 1.0
                slot.node.position = SCNVector3(x, y, spec.depth / 2 - 0.01)
                node.addChildNode(slot.node)
                slots.append(slot)
                idx += 1
            }
        }
        // World-space helpers
        let yaw = atan2(spec.normal.x, spec.normal.y)
        let right = SIMD2<Float>(cos(yaw), -sin(yaw))
        for slot in slots {
            let lx = slot.node.position.x
            let base = spec.center + right * lx
            slot.standPoint = base + spec.normal * (spec.depth / 2 + 0.6)
            let front = base + spec.normal * (spec.depth / 2 - 0.2)
            slot.worldCenter = SIMD3(front.x, slot.node.position.y + 0.2, front.y)
        }
    }

    private func buildFrame(shelfColor: UInt32) {
        let L = spec.length, D = spec.depth, H = spec.height
        let isCold = spec.kind != .shelf
        let frameColor: UInt32 = isCold ? (spec.kind == .fridge ? 0x3B4651 : 0xE3EEF4) : shelfColor
        let backColor: UInt32 = isCold ? 0xF4F8FA : shelfColor

        func add(_ n: SCNNode, _ x: Float, _ y: Float, _ z: Float) {
            n.position = SCNVector3(x, y, z)
            node.addChildNode(n)
        }
        add(Models.box(L, 0.1, D, frameColor), 0, 0.05, 0)
        add(Models.box(L, H, 0.04, backColor), 0, H / 2, -D / 2 + 0.02)
        add(Models.box(0.04, H, D, frameColor), -L / 2 + 0.02, H / 2, 0)
        add(Models.box(0.04, H, D, frameColor), L / 2 - 0.02, H / 2, 0)
        add(Models.box(L, 0.05, D, frameColor), 0, H - 0.025, 0)
        add(Models.box(0.04, H - 0.1, D - 0.04, frameColor), 0, H / 2, 0)   // middle divider
        for y in spec.levelHeights.dropFirst() {
            add(Models.box(L - 0.06, 0.025, D - 0.04, isCold ? 0xC9D6DF : shelfColor), 0, y - 0.0125, 0.0)
        }
        // Front shelf lips (where price tags go)
        for y in spec.levelHeights {
            add(Models.box(L - 0.06, 0.06, 0.012, isCold ? 0x9FB0BC : 0x8A9097), 0, y - 0.03, D / 2 - 0.006)
        }
        if isCold {
            // Light strip and glass doors
            let strip = SCNNode(geometry: SCNBox(width: CGFloat(L - 0.1), height: 0.03, length: 0.03, chamferRadius: 0))
            strip.geometry?.firstMaterial = Models.emissive(0xE8F8FF)
            add(strip, 0, H - 0.08, D / 2 - 0.05)
            let glass = SCNNode(geometry: SCNBox(width: CGFloat(L - 0.06), height: CGFloat(H - 0.16), length: 0.015, chamferRadius: 0))
            glass.geometry?.firstMaterial = Models.freshMat(spec.kind == .fridge ? 0xBFE6FF : 0xDDF3FF, alpha: 0.16)
            glass.categoryBitMask = Models.categoryNoHit
            add(glass, 0, H / 2 + 0.03, D / 2 + 0.008)
            for x in [-L / 4, L / 4] {
                let handle = Models.box(0.025, 0.5, 0.03, 0xB8C2CA)
                handle.categoryBitMask = Models.categoryNoHit
                add(handle, x + (x < 0 ? L / 4 - 0.08 : -L / 4 + 0.08), 1.1, D / 2 + 0.03)
            }
        }
    }
}
