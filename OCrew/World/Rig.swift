import SceneKit
import simd
import UIKit

/// First-person arms: left hand carries the basket, right hand reaches out to grab and place.
/// Everything lives in camera space (x right, y up, -z forward).
@MainActor
final class FirstPersonRig {
    let root = SCNNode()
    let basketHolder = SCNNode()
    private let rightArm = SCNNode()
    private let leftArm = SCNNode()
    private var fingers: [SCNNode] = []
    private var knuckles: [SCNNode] = []
    private var thumb = SCNNode()
    private var reachStart: Double = -10
    private var sway = SIMD2<Float>(0, 0)
    private let rightRest = SIMD3<Float>(0, 0, 0)

    init(sleeve: UInt32, skin: UInt32) {
        let sleeveMat = Models.freshMat(sleeve)
        let cuffMat = Models.freshMat(0xF4F6F7)
        let skinMat = Models.freshMat(skin)

        // ---- Right arm (reaching hand)
        let rElbow = SIMD3<Float>(0.42, -0.44, -0.14)
        let rWrist = SIMD3<Float>(0.25, -0.21, -0.5)
        let rMid = rElbow + (rWrist - rElbow) * 0.55
        rightArm.addChildNode(Self.limb(from: rElbow + SIMD3(0.05, -0.08, 0.12), to: rMid, radius: 0.058, mat: sleeveMat))
        rightArm.addChildNode(Self.limb(from: rMid - (rWrist - rElbow) * 0.03, to: rMid + (rWrist - rElbow) * 0.03, radius: 0.06, mat: cuffMat))
        rightArm.addChildNode(Self.limb(from: rMid, to: rWrist, radius: 0.04, mat: skinMat))
        let hand = Self.hand(skin: skinMat, mirrored: false, fingers: &fingers, thumb: &thumb)
        hand.simdPosition = rWrist
        hand.simdOrientation = simd_quatf(angle: 0.35, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -0.25, axis: SIMD3(1, 0, 0))
        rightArm.addChildNode(hand)
        root.addChildNode(rightArm)

        // ---- Left arm (holds the basket handle)
        let lElbow = SIMD3<Float>(-0.46, -0.46, -0.12)
        let lWrist = SIMD3<Float>(-0.31, -0.25, -0.47)
        let lMid = lElbow + (lWrist - lElbow) * 0.55
        leftArm.addChildNode(Self.limb(from: lElbow + SIMD3(-0.05, -0.08, 0.12), to: lMid, radius: 0.058, mat: sleeveMat))
        leftArm.addChildNode(Self.limb(from: lMid - (lWrist - lElbow) * 0.03, to: lMid + (lWrist - lElbow) * 0.03, radius: 0.06, mat: cuffMat))
        leftArm.addChildNode(Self.limb(from: lMid, to: lWrist, radius: 0.04, mat: skinMat))
        // A closed fist around the handle
        let fist = SCNNode(geometry: SCNBox(width: 0.075, height: 0.08, length: 0.09, chamferRadius: 0.03))
        fist.geometry?.firstMaterial = skinMat
        fist.simdPosition = lWrist + SIMD3(0.01, -0.035, -0.03)
        leftArm.addChildNode(fist)
        for i in 0..<4 {
            let k = SCNNode(geometry: SCNSphere(radius: 0.016))
            k.geometry?.firstMaterial = skinMat
            k.simdPosition = lWrist + SIMD3(0.035, -0.012 - Float(i) * 0.02, -0.065)
            leftArm.addChildNode(k)
        }
        basketHolder.simdPosition = lWrist + SIMD3(0.0, -0.08, -0.03)
        leftArm.addChildNode(basketHolder)
        root.addChildNode(leftArm)

        knuckles = fingers.compactMap { $0.childNode(withName: "knuckle", recursively: false) }
        Models.setCategory(root, 2)
    }

    /// A capsule from a to b.
    static func limb(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: Float, mat: SCNMaterial) -> SCNNode {
        let d = b - a
        let len = max(0.001, simd_length(d))
        let g = SCNCapsule(capRadius: CGFloat(radius), height: CGFloat(len + radius * 2))
        g.radialSegmentCount = 14
        g.capSegmentCount = 6
        g.firstMaterial = mat
        let n = SCNNode(geometry: g)
        n.simdPosition = (a + b) / 2
        n.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: d / len)
        return n
    }

    private static func hand(skin: SCNMaterial, mirrored: Bool, fingers: inout [SCNNode], thumb: inout SCNNode) -> SCNNode {
        let h = SCNNode()
        let palm = SCNNode(geometry: SCNBox(width: 0.085, height: 0.032, length: 0.1, chamferRadius: 0.014))
        palm.geometry?.firstMaterial = skin
        palm.position = SCNVector3(0, 0, -0.045)
        h.addChildNode(palm)
        let lengths: [Float] = [0.062, 0.072, 0.068, 0.054]
        for i in 0..<4 {
            let pivot = SCNNode()
            pivot.position = SCNVector3(-0.03 + Float(i) * 0.02, 0, -0.095)
            let seg1 = SCNNode(geometry: SCNCapsule(capRadius: 0.0105, height: CGFloat(lengths[i] * 0.55 + 0.021)))
            seg1.geometry?.firstMaterial = skin
            seg1.eulerAngles.x = -Float.pi / 2
            seg1.position = SCNVector3(0, 0, -lengths[i] * 0.275)
            pivot.addChildNode(seg1)
            let knuckle = SCNNode()
            knuckle.position = SCNVector3(0, 0, -lengths[i] * 0.55)
            let seg2 = SCNNode(geometry: SCNCapsule(capRadius: 0.0095, height: CGFloat(lengths[i] * 0.45 + 0.019)))
            seg2.geometry?.firstMaterial = skin
            seg2.eulerAngles.x = -Float.pi / 2
            seg2.position = SCNVector3(0, 0, -lengths[i] * 0.225)
            knuckle.addChildNode(seg2)
            knuckle.name = "knuckle"
            pivot.addChildNode(knuckle)
            pivot.eulerAngles.x = -0.25        // relaxed curl
            knuckle.eulerAngles.x = -0.35
            h.addChildNode(pivot)
            fingers.append(pivot)
        }
        let t = SCNNode()
        t.position = SCNVector3(-0.045, -0.006, -0.03)
        let tseg = SCNNode(geometry: SCNCapsule(capRadius: 0.012, height: 0.07))
        tseg.geometry?.firstMaterial = skin
        tseg.eulerAngles.x = -Float.pi / 2
        tseg.position = SCNVector3(0, 0, -0.028)
        t.addChildNode(tseg)
        t.eulerAngles.y = 0.6
        h.addChildNode(t)
        thumb = t
        return h
    }

    /// Plays the reach-and-grab motion.
    func reach(now: Double) { reachStart = now }

    func update(dt: Float, now: Double, move: Float, bobPhase: Float, lookDelta: SIMD2<Float>, reduceMotion: Bool) {
        // Sway: the arms lag a little behind fast looks.
        let target = reduceMotion ? SIMD2<Float>(0, 0) : SIMD2(max(-1, min(1, -lookDelta.x * 0.004)), max(-1, min(1, lookDelta.y * 0.004)))
        sway += (target - sway) * min(1, dt * 10)
        let walk: Float = reduceMotion ? 0 : move
        let bobX = sin(bobPhase) * 0.016 * walk
        let bobY = -abs(sin(bobPhase)) * 0.022 * walk
        let breathe: Float = reduceMotion ? 0 : sin(Float(now) * 1.7) * 0.004
        root.simdPosition = SIMD3(bobX + sway.x * 0.05, bobY + breathe + sway.y * 0.04, 0)
        root.simdEulerAngles = SIMD3(sway.y * 0.06, sway.x * 0.08, -bobX * 1.2)

        // Basket swings opposite to the step.
        leftArm.simdEulerAngles = SIMD3(sin(bobPhase * 2) * 0.03 * walk, 0, sin(bobPhase) * 0.025 * walk)

        // Reach: push the right hand forward and close the fingers, then come back.
        let t = Float(now - reachStart)
        let dur: Float = 0.26
        var e: Float = 0
        if t >= 0 && t < dur { e = sin(t / dur * .pi) }
        rightArm.simdPosition = rightRest + SIMD3(-0.03 * e, 0.06 * e, -0.16 * e)
        rightArm.simdEulerAngles = SIMD3(0.12 * e, 0.1 * e, 0)
        for f in fingers { f.eulerAngles.x = -0.25 - 0.9 * e }
        for k in knuckles { k.eulerAngles.x = -0.35 - 0.9 * e }
        thumb.eulerAngles.y = 0.6 - 0.5 * e
    }
}
