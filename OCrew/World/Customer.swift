import SceneKit
import simd

@MainActor
final class Customer {
    enum State {
        case entering, toShelf, picking, toQueue, queued, atCounter, waitingPayment, leaving, stealing
    }

    let id: Int
    let node = SCNNode()
    private let body = SCNNode()
    private let legL = SCNNode(), legR = SCNNode()
    private let armL = SCNNode(), armR = SCNNode()
    private let basketNode: SCNNode
    private let barRoot = SCNNode()
    private let barFill: SCNNode
    private let shirtMat: SCNMaterial

    var pos: SIMD2<Float>
    var heading: Float = 0
    var path: [SIMD2<Float>] = []
    var speed: Float
    var state: State = .entering
    var timer: Double = 0

    var list: [(product: String, qty: Int)] = []
    var listIndex = 0
    var targetSlot: (fixture: Int, slot: Int)?
    var basket: [String] = []
    var patience: Double = 1
    var penalties: Double = 0
    var bonus: Double = 0
    var isThief = false
    var paysCash = false
    var cashTendered: Double = 0
    var waved = false
    var queueIndex = -1
    var missing: [String] = []
    var lastStuckCheck: SIMD2<Float> = .zero
    var stuckTime: Double = 0

    private var walkPhase: Float = 0
    private var highlighted = false

    private static let skin: [UInt32] = [0xF1C27D, 0xE0AC69, 0xC68642, 0x8D5524, 0xFFDBAC, 0x6B4226]
    private static let shirts: [UInt32] = [0x2E86C1, 0xC0392B, 0x27AE60, 0x8E44AD, 0xF39C12, 0x16A085, 0x34495E, 0xD35400, 0xEC7063, 0x5D6D7E, 0xF4D03F]
    private static let pants: [UInt32] = [0x1B2631, 0x34495E, 0x5D4037, 0x2C3E50, 0x7F8C8D, 0x1A5276]
    private static let hair: [UInt32] = [0x1C1C1C, 0x3E2723, 0x6D4C41, 0xD4AC0D, 0x9E9E9E, 0xA0522D]

    init(id: Int, at p: SIMD2<Float>) {
        // Build the pieces that are stored as `let` first.
        let shirt = Models.freshMat(Self.shirts.randomElement()!)
        let basket = SCNNode()
        let b = SCNNode(geometry: SCNBox(width: 0.34, height: 0.18, length: 0.24, chamferRadius: 0.02))
        b.geometry?.firstMaterial = Models.mat(0xD62828)
        basket.addChildNode(b)
        let handle = SCNNode(geometry: SCNTorus(ringRadius: 0.1, pipeRadius: 0.012))
        handle.geometry?.firstMaterial = Models.mat(0x222222)
        handle.eulerAngles.z = Float.pi / 2
        handle.position.y = 0.1
        basket.addChildNode(handle)
        basket.position = SCNVector3(0.0, -0.5, 0.05)
        basket.isHidden = true

        let fill = SCNNode(geometry: SCNPlane(width: 0.48, height: 0.045))
        let fm = SCNMaterial()
        fm.lightingModel = .constant
        fm.readsFromDepthBuffer = false
        fm.diffuse.contents = UIColor.green
        fill.geometry?.firstMaterial = fm
        fill.position.z = 0.001
        fill.renderingOrder = 91

        self.id = id
        self.pos = p
        self.speed = Float.random(in: 1.05...1.45)
        self.shirtMat = shirt
        self.basketNode = basket
        self.barFill = fill

        let skinMat = Models.mat(Self.skin.randomElement()!)
        let pantsMat = Models.mat(Self.pants.randomElement()!)

        node.name = "cust:\(id)"
        node.addChildNode(body)

        // Legs (pivot at hip)
        for (leg, x) in [(legL, Float(-0.1)), (legR, Float(0.1))] {
            leg.position = SCNVector3(x, 0.86, 0)
            let g = SCNBox(width: 0.13, height: 0.84, length: 0.15, chamferRadius: 0.03)
            g.firstMaterial = pantsMat
            let n = SCNNode(geometry: g)
            n.position.y = -0.42
            leg.addChildNode(n)
            let shoe = SCNNode(geometry: SCNBox(width: 0.14, height: 0.08, length: 0.24, chamferRadius: 0.03))
            shoe.geometry?.firstMaterial = Models.mat(0x222222)
            shoe.position = SCNVector3(0, -0.82, 0.04)
            leg.addChildNode(shoe)
            body.addChildNode(leg)
        }
        // Torso
        let torso = SCNNode(geometry: SCNBox(width: 0.44, height: 0.62, length: 0.26, chamferRadius: 0.07))
        torso.geometry?.firstMaterial = shirt
        torso.position.y = 1.16
        body.addChildNode(torso)
        // Arms (pivot at shoulder)
        for (arm, x) in [(armL, Float(-0.28)), (armR, Float(0.28))] {
            arm.position = SCNVector3(x, 1.42, 0)
            let sleeve = SCNNode(geometry: SCNBox(width: 0.11, height: 0.3, length: 0.13, chamferRadius: 0.03))
            sleeve.geometry?.firstMaterial = shirt
            sleeve.position.y = -0.14
            arm.addChildNode(sleeve)
            let hand = SCNNode(geometry: SCNBox(width: 0.09, height: 0.3, length: 0.1, chamferRadius: 0.03))
            hand.geometry?.firstMaterial = skinMat
            hand.position.y = -0.42
            arm.addChildNode(hand)
            body.addChildNode(arm)
        }
        // Head
        let neck = SCNNode(geometry: SCNCylinder(radius: 0.06, height: 0.08))
        neck.geometry?.firstMaterial = skinMat
        neck.position.y = 1.5
        body.addChildNode(neck)
        let head = SCNNode(geometry: SCNSphere(radius: 0.14))
        head.geometry?.firstMaterial = skinMat
        head.position.y = 1.64
        body.addChildNode(head)
        let hairNode = SCNNode(geometry: SCNSphere(radius: 0.148))
        hairNode.geometry?.firstMaterial = Models.mat(Self.hair.randomElement()!)
        hairNode.position = SCNVector3(0, 1.69, -0.025)
        hairNode.scale = SCNVector3(1, 0.72, 1)
        body.addChildNode(hairNode)
        for x in [Float(-0.05), Float(0.05)] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.018))
            eye.geometry?.firstMaterial = Models.mat(0x111111)
            eye.position = SCNVector3(x, 1.66, 0.128)
            body.addChildNode(eye)
        }
        armR.addChildNode(basket)

        // Patience bar
        let bg = SCNNode(geometry: SCNPlane(width: 0.52, height: 0.075))
        let bgm = SCNMaterial()
        bgm.diffuse.contents = UIColor(white: 0, alpha: 0.6)
        bgm.lightingModel = .constant
        bgm.readsFromDepthBuffer = false
        bg.geometry?.firstMaterial = bgm
        bg.renderingOrder = 90
        barRoot.addChildNode(bg)
        barRoot.addChildNode(fill)
        barRoot.position.y = 2.02
        barRoot.constraints = [SCNBillboardConstraint()]
        node.addChildNode(barRoot)
        Models.setCategory(barRoot, Models.categoryNoHit)

        node.simdPosition = SIMD3(p.x, 0, p.y)
    }

    var totalItems: Int { basket.count }

    func showBasket(_ on: Bool) { basketNode.isHidden = !on }

    func setPatienceBar(visible: Bool, colorblind: ColorblindMode) {
        barRoot.isHidden = !visible
        guard visible else { return }
        let p = Float(max(0, min(1, patience)))
        barFill.scale = SCNVector3(max(0.001, p), 1, 1)
        barFill.position.x = -0.24 * (1 - p)
        barFill.geometry?.firstMaterial?.diffuse.contents = UIColor(hex: StatusPalette.forLevel(Double(p), colorblind))
    }

    func setHighlighted(_ on: Bool, time: Double) {
        if on {
            let pulse = 0.55 + 0.45 * sin(time * 8)
            shirtMat.emission.contents = UIColor(red: CGFloat(pulse), green: 0.05, blue: 0.05, alpha: 1)
            highlighted = true
        } else if highlighted {
            shirtMat.emission.contents = UIColor.black
            highlighted = false
        }
    }

    /// Moves along the path. Returns true when the path is finished.
    @discardableResult
    func follow(dt: Float, speedMul: Float = 1) -> Bool {
        guard let target = path.first else { animate(moving: false, dt: dt); return true }
        let delta = target - pos
        let dist = simd_length(delta)
        let step = speed * speedMul * dt
        if dist <= step {
            pos = target
            path.removeFirst()
        } else {
            pos += delta / dist * step
        }
        if dist > 0.001 {
            let want = atan2(delta.x, delta.y)
            heading = lerpAngle(heading, want, min(1, dt * 10))
        }
        node.simdPosition = SIMD3(pos.x, 0, pos.y)
        node.simdEulerAngles = SIMD3(0, heading, 0)
        animate(moving: true, dt: dt * speedMul)
        return path.isEmpty
    }

    func face(_ p: SIMD2<Float>) {
        let d = p - pos
        if simd_length(d) > 0.01 { heading = atan2(d.x, d.y) }
        node.simdEulerAngles = SIMD3(0, heading, 0)
    }

    func animate(moving: Bool, dt: Float) {
        if moving {
            walkPhase += dt * speed * 6.5
        } else {
            walkPhase *= 0.85
        }
        let swing = sin(walkPhase) * (moving ? 0.5 : 0)
        legL.eulerAngles.x = swing
        legR.eulerAngles.x = -swing
        armL.eulerAngles.x = -swing * 0.7
        armR.eulerAngles.x = basketNode.isHidden ? swing * 0.7 : 0
        body.position.y = moving ? abs(sin(walkPhase)) * 0.035 : 0
    }

    private func lerpAngle(_ a: Float, _ b: Float, _ t: Float) -> Float {
        var d = b - a
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return a + d * t
    }
}
