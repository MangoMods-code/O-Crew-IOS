import SceneKit
import simd
import UIKit

/// A jointed hand: rounded palm, three-segment fingers, two-segment thumb.
/// Local space: fingers point toward -z, back of the hand faces +y.
@MainActor
final class Hand {
    let root = SCNNode()
    /// [finger][joint] pivots; rotating a joint about x by a negative angle curls it.
    private(set) var joints: [[SCNNode]] = []
    private(set) var thumbJoints: [SCNNode] = []
    private let mirrored: Bool

    init(skin: SCNMaterial, mirrored: Bool, thickness: Float = 1.18) {
        self.mirrored = mirrored
        let sx: Float = mirrored ? -1 : 1

        // Palm: a rounded slab, slightly wider at the knuckles.
        let palm = SCNNode(geometry: SCNBox(width: 0.084, height: 0.032, length: 0.09, chamferRadius: 0.015))
        palm.geometry?.firstMaterial = skin
        palm.position = SCNVector3(0, 0, -0.045)
        root.addChildNode(palm)
        let heel = SCNNode(geometry: SCNCapsule(capRadius: 0.016, height: 0.07))
        heel.geometry?.firstMaterial = skin
        heel.eulerAngles.z = Float.pi / 2
        heel.position = SCNVector3(0, -0.004, -0.008)
        root.addChildNode(heel)

        // Fingers: index (thumb side) to pinky.
        let xs: [Float] = [-0.027, -0.009, 0.009, 0.026]
        let lengths: [[Float]] = [[0.040, 0.025, 0.020], [0.044, 0.028, 0.021], [0.041, 0.026, 0.020], [0.032, 0.020, 0.017]]
        let radii: [Float] = [0.0098, 0.0102, 0.0096, 0.0086]
        let baseZ: [Float] = [-0.088, -0.091, -0.089, -0.083]
        for i in 0..<4 {
            var chain: [SCNNode] = []
            var parent = root
            var z = baseZ[i]
            for j in 0..<3 {
                let pivot = SCNNode()
                pivot.position = SCNVector3(j == 0 ? xs[i] * sx : 0, 0, j == 0 ? z : -lengths[i][j - 1])
                if j == 0 { pivot.eulerAngles.y = -xs[i] * sx * 1.6 }   // slight natural spread
                let r = radii[i] * thickness * (1 - Float(j) * 0.06)
                let seg = SCNNode(geometry: SCNCapsule(capRadius: CGFloat(r), height: CGFloat(lengths[i][j] + r * 2)))
                seg.geometry?.firstMaterial = skin
                seg.eulerAngles.x = -Float.pi / 2
                seg.position = SCNVector3(0, 0, -lengths[i][j] / 2)
                pivot.addChildNode(seg)
                parent.addChildNode(pivot)
                chain.append(pivot)
                parent = pivot
                z = 0
            }
            joints.append(chain)
        }
        // Thumb: comes off the side of the palm, angled forward and down.
        let tBase = SCNNode()
        tBase.position = SCNVector3(-0.037 * sx, -0.008, -0.022)
        tBase.eulerAngles = SCNVector3(-0.25, 0.85 * sx, 0.35 * sx)
        root.addChildNode(tBase)
        var parent = tBase
        for (j, len) in [Float(0.036), 0.027].enumerated() {
            let pivot = SCNNode()
            pivot.position = SCNVector3(0, 0, j == 0 ? 0 : -0.036)
            let r: Float = j == 0 ? 0.0125 : 0.0108
            let seg = SCNNode(geometry: SCNCapsule(capRadius: CGFloat(r), height: CGFloat(len + r * 2)))
            seg.geometry?.firstMaterial = skin
            seg.eulerAngles.x = -Float.pi / 2
            seg.position = SCNVector3(0, 0, -len / 2)
            pivot.addChildNode(seg)
            parent.addChildNode(pivot)
            thumbJoints.append(pivot)
            parent = pivot
        }
    }

    /// 0 = open and relaxed, 1 = tight fist.
    func pose(curl: Float, thumb: Float) {
        let base: [Float] = [0.18, 0.22, 0.26, 0.3]   // relaxed hands are never perfectly straight
        for (i, chain) in joints.enumerated() {
            let c = base[i] + curl * 1.35
            chain[0].eulerAngles.x = -c
            chain[1].eulerAngles.x = -(base[i] * 1.4 + curl * 1.55)
            chain[2].eulerAngles.x = -(base[i] + curl * 1.1)
        }
        if thumbJoints.count == 2 {
            thumbJoints[0].eulerAngles.x = -0.15 - thumb * 0.5
            thumbJoints[1].eulerAngles.x = -0.25 - thumb * 0.9
        }
    }
}

/// First-person arms: left hand carries the basket, right hand reaches out to grab and place.
/// Everything lives in camera space (x right, y up, -z forward).
@MainActor
final class FirstPersonRig {
    let root = SCNNode()
    let basketHolder = SCNNode()
    private let rightArm = SCNNode()
    private let leftArm = SCNNode()
    private let rightHand: Hand
    private let leftHand: Hand
    private var reachStart: Double = -10
    private var sway = SIMD2<Float>(0, 0)

    init(sleeve: UInt32, skin: UInt32) {
        let sleeveMat = SCNMaterial()
        sleeveMat.diffuse.contents = UIColor(hex: sleeve)
        sleeveMat.lightingModel = .lambert
        let glove = SCNMaterial()
        glove.diffuse.contents = UIColor(hex: 0x2E3B48)
        glove.specular.contents = UIColor(white: 0.22, alpha: 1)
        glove.shininess = 0.3
        glove.lightingModel = .blinn
        let cuff = SCNMaterial()
        cuff.diffuse.contents = UIColor(hex: Theme.brand)
        cuff.lightingModel = .lambert

        rightHand = Hand(skin: glove, mirrored: false)
        leftHand = Hand(skin: glove, mirrored: true)

        // ---- Right arm: lives just below the screen and sweeps up to grab/place.
        let rElbow = SIMD3<Float>(0.4, -0.44, -0.08)
        let rWrist = SIMD3<Float>(0.22, -0.2, -0.46)
        Self.buildForearm(into: rightArm, elbow: rElbow, wrist: rWrist, sleeve: sleeveMat, cuff: cuff)
        rightHand.root.simdPosition = rWrist
        rightHand.root.simdOrientation = simd_quatf(angle: 0.3, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: -0.12, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: -0.25, axis: SIMD3(0, 0, 1))
        rightArm.addChildNode(rightHand.root)
        rightHand.pose(curl: 0, thumb: 0)
        rightArm.isHidden = true
        root.addChildNode(rightArm)

        // ---- Left arm: gloved fist on the basket handle, tucked into the bottom-left corner.
        let lElbow = SIMD3<Float>(-0.46, -0.48, -0.08)
        let lWrist = SIMD3<Float>(-0.34, -0.29, -0.45)
        Self.buildForearm(into: leftArm, elbow: lElbow, wrist: lWrist, sleeve: sleeveMat, cuff: cuff)
        leftHand.root.simdPosition = lWrist
        leftHand.root.simdOrientation = simd_quatf(angle: -0.25, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: 1.3, axis: SIMD3(0, 0, 1))
            * simd_quatf(angle: -0.15, axis: SIMD3(1, 0, 0))
        leftHand.pose(curl: 1.0, thumb: 0.85)
        leftArm.addChildNode(leftHand.root)
        basketHolder.simdPosition = lWrist + SIMD3(0.012, -0.04, -0.065)
        basketHolder.scale = SCNVector3(0.72, 0.72, 0.72)
        leftArm.addChildNode(basketHolder)
        root.addChildNode(leftArm)

        Models.setCategory(root, 2)
    }

    private static func buildForearm(into arm: SCNNode, elbow: SIMD3<Float>, wrist: SIMD3<Float>,
                                     sleeve: SCNMaterial, cuff: SCNMaterial) {
        let dir = simd_normalize(wrist - elbow)
        // Long uniform sleeve right down to a glove cuff at the wrist.
        arm.addChildNode(limb(from: elbow - dir * 0.15, to: elbow + (wrist - elbow) * 0.45, radius: 0.05, mat: sleeve))
        arm.addChildNode(limb(from: elbow + (wrist - elbow) * 0.4, to: wrist - dir * 0.03, radius: 0.043, mat: sleeve))
        arm.addChildNode(limb(from: wrist - dir * 0.035, to: wrist + dir * 0.005, radius: 0.036, mat: cuff))
    }

    /// A capsule from a to b.
    static func limb(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: Float, mat: SCNMaterial) -> SCNNode {
        let d = b - a
        let len = max(0.001, simd_length(d))
        let g = SCNCapsule(capRadius: CGFloat(radius), height: CGFloat(len + radius * 2))
        g.radialSegmentCount = 16
        g.capSegmentCount = 8
        g.firstMaterial = mat
        let n = SCNNode(geometry: g)
        n.simdPosition = (a + b) / 2
        n.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: d / len)
        return n
    }

    /// Plays the reach-and-grab motion.
    func reach(now: Double) { reachStart = now }

    func update(dt: Float, now: Double, move: Float, bobPhase: Float, lookDelta: SIMD2<Float>, reduceMotion: Bool) {
        // Sway: the arms lag a little behind fast looks.
        let target = reduceMotion ? SIMD2<Float>(0, 0) : SIMD2(max(-1, min(1, -lookDelta.x * 0.004)), max(-1, min(1, lookDelta.y * 0.004)))
        sway += (target - sway) * min(1, dt * 10)
        let walk: Float = reduceMotion ? 0 : move
        let bobX = sin(bobPhase) * 0.014 * walk
        let bobY = -abs(sin(bobPhase)) * 0.02 * walk
        let breathe: Float = reduceMotion ? 0 : sin(Float(now) * 1.7) * 0.0035
        root.simdPosition = SIMD3(bobX + sway.x * 0.05, bobY + breathe + sway.y * 0.04, 0)
        root.simdEulerAngles = SIMD3(sway.y * 0.06, sway.x * 0.08, -bobX * 1.1)

        // Arms swing a little with each step, opposite to each other.
        leftArm.simdEulerAngles = SIMD3(sin(bobPhase * 2) * 0.025 * walk, 0, sin(bobPhase) * 0.02 * walk)

        // Reach: the right hand sweeps up from below the screen, opens, grips, and drops away.
        let t = Float(now - reachStart)
        let dur: Float = 0.32
        var e: Float = 0
        if t >= 0 && t < dur { e = sin(t / dur * .pi) }
        rightArm.isHidden = e <= 0.001
        if !rightArm.isHidden {
            let ease = e * e * (3 - 2 * e)
            rightArm.simdPosition = SIMD3(-0.03 * ease, -0.3 * (1 - ease) + 0.03 * ease, -0.12 * ease)
            rightArm.simdEulerAngles = SIMD3(0.12 * ease, 0.06 * ease, 0)
            let p = t / dur
            let grip: Float = p < 0.4 ? 0 : min(1, (p - 0.4) / 0.25)
            rightHand.pose(curl: 0.05 + grip * 0.85, thumb: grip * 0.9)
        }
    }
}
