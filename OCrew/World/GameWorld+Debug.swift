import SceneKit
import simd

/// Staged states for the automated screenshot run.
extension GameWorld {
    func debugFill(_ fraction: Double) {
        let all = floorItems.values.sorted { $0.id < $1.id }
        let n = Int(Double(all.count) * fraction)
        for it in all.prefix(n) {
            if it.expired {
                removeFromFloor(it)
                items[it.id] = nil
                binned += 1
                continue
            }
            guard let slot = correctSlot(for: it) else { continue }
            removeFromFloor(it)
            slot.items.append(it)
        }
        for f in fixtures {
            for s in f.slots {
                s.rebuild()
                s.refreshTag(visible: display.showShelfTags)
            }
        }
        rebuildChunks()
        for cat in Set(fixtures.flatMap { $0.slots }.compactMap { $0.category }) where sectionDone(cat) { completedSections.insert(cat) }
        refreshSigns()
    }

    func debugLook(x: Float, z: Float, yaw y: Float, pitch p: Float) {
        playerPos = SIMD2(x, z)
        yaw = y; targetYaw = y
        pitch = p; targetPitch = p
    }

    func debugStage(_ pose: Int) {
        tutorialActive = false
        let W = layout.width, D = layout.depth
        switch pose {
        case 1:
            debugFill(0.6)
            debugLook(x: W / 2, z: D * 0.6, yaw: 0, pitch: -0.05)
        case 2:
            debugFill(0.3)
            for it in floorItems.values.sorted(by: { $0.id < $1.id }).prefix(9) { pickUp(it.id) }
            debugLook(x: W / 2, z: D * 0.5, yaw: 0.4, pitch: -0.85)
        case 3:
            debugFill(0.8)
            debugLook(x: min(W - 1, 3.4), z: D * 0.4, yaw: Float.pi / 2, pitch: 0)
        case 4:
            debugFill(1.0)
            debugLook(x: W / 2, z: D * 0.6, yaw: 0, pitch: -0.05)
            checkComplete()
        case 5:
            debugFill(0.5)
            debugLook(x: W / 2, z: D * 0.45, yaw: Float.pi, pitch: -0.1)
        case 6:
            debugFill(0.9)
            debugLook(x: W / 2, z: 2.2, yaw: 0, pitch: 0)
        default:
            break
        }
    }
}
