import SceneKit
import simd
import UIKit

/// Our own tap/aim detection: a ray against simple boxes. Much cheaper than SceneKit's
/// hit test, which had to check every mesh in the store.
extension GameWorld {
    /// Ray vs axis-aligned box. Returns the entry distance, or nil.
    private func hitAABB(_ o: SIMD3<Float>, _ d: SIMD3<Float>, _ mn: SIMD3<Float>, _ mx: SIMD3<Float>) -> Float? {
        var tmin: Float = 0, tmax = Float.greatestFiniteMagnitude
        for i in 0..<3 {
            if abs(d[i]) < 1e-6 {
                if o[i] < mn[i] || o[i] > mx[i] { return nil }
            } else {
                var t1 = (mn[i] - o[i]) / d[i], t2 = (mx[i] - o[i]) / d[i]
                if t1 > t2 { swap(&t1, &t2) }
                tmin = max(tmin, t1)
                tmax = min(tmax, t2)
                if tmin > tmax { return nil }
            }
        }
        return tmin
    }

    private func itemBox(_ it: Item) -> (center: SIMD3<Float>, half: SIMD3<Float>) {
        let c = cos(it.yaw), s = sin(it.yaw)
        let lc = it.hitCenter
        // Rotation about y by yaw: x' = x c + z s, z' = -x s + z c
        let wc = SIMD3<Float>(it.floorPos.x + lc.x * c + lc.z * s, lc.y, it.floorPos.y - lc.x * s + lc.z * c)
        return (wc, it.hitHalf)
    }

    /// What the ray points at, within reach.
    func raycast(origin o: SIMD3<Float>, dir rawDir: SIMD3<Float>) -> Target? {
        let len = simd_length(rawDir)
        guard len > 0 else { return nil }
        let d = rawDir / len
        let itemReach = Float(game.pickupReach)
        let reach: Float = 2.7
        var best: Float = max(itemReach, reach) + 0.01
        var hit: Target?

        // Blockers: shelf backs/ends (so you can't grab through a shelf)
        for f in fixtures {
            for b in f.occluders {
                if let t = hitAABB(o, d, b.0, b.1), t < best { best = t; hit = nil }
            }
        }
        // Shelf spots
        for f in fixtures {
            for sl in f.slots {
                if let t = hitAABB(o, d, sl.boxMin, sl.boxMax), t <= best, t <= reach {
                    best = t
                    hit = .slot(f.index, sl.index)
                }
            }
        }
        // Floor items (oriented boxes: move the ray into the item's frame)
        for it in floorItems.values {
            let dx = it.floorPos.x - o.x, dz = it.floorPos.y - o.z
            if dx * dx + dz * dz > (itemReach + 0.6) * (itemReach + 0.6) { continue }
            let box = itemBox(it)
            let c = cos(-it.yaw), s = sin(-it.yaw)
            let ro = o - box.center
            let lo = SIMD3<Float>(ro.x * c + ro.z * s, ro.y, -ro.x * s + ro.z * c)
            let ld = SIMD3<Float>(d.x * c + d.z * s, d.y, -d.x * s + d.z * c)
            if let t = hitAABB(lo, ld, -box.half, box.half), t <= best, t <= itemReach {
                best = t
                hit = .item(it.id)
            }
        }
        // Trash bin
        let bn = SIMD3<Float>(layout.bin.minX, 0, layout.bin.minZ), bx = SIMD3<Float>(layout.bin.maxX, 0.95, layout.bin.maxZ)
        if let t = hitAABB(o, d, bn, bx), t <= best, t <= reach {
            hit = .bin
        }
        return hit
    }

    func setHighlight(_ t: Target?) {
        guard display.highlightFocused, let t = t else {
            highlightNode.isHidden = true
            return
        }
        var center = SIMD3<Float>(0, 0, 0), size = SIMD3<Float>(0, 0, 0), yawA: Float = 0
        switch t {
        case let .item(id):
            guard let it = floorItems[id] else { highlightNode.isHidden = true; return }
            let b = itemBox(it)
            center = b.center; size = b.half * 2; yawA = it.yaw
        case let .slot(f, s):
            guard let sl = fixtures[safe: f]?.slots[safe: s] else { highlightNode.isHidden = true; return }
            center = (sl.boxMin + sl.boxMax) / 2; size = sl.boxMax - sl.boxMin
        case .bin:
            center = SIMD3(layout.bin.center.x, 0.45, layout.bin.center.y)
            size = SIMD3(layout.bin.size.x, 0.9, layout.bin.size.y)
        }
        let m = Models.translate(center.x, center.y, center.z) * Models.rotate(yawA, SIMD3(0, 1, 0))
        var sc = matrix_identity_float4x4
        let sz = size * 1.04 + 0.01
        sc.columns.0.x = sz.x; sc.columns.1.y = sz.y; sc.columns.2.z = sz.z
        highlightNode.simdTransform = m * sc
        let pulse = 0.12 + 0.06 * sin(time * 5)
        highlightNode.opacity = CGFloat(pulse / 0.16)
        highlightNode.isHidden = false
    }
}
