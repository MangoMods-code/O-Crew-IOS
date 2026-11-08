import Foundation
import GameplayKit
import simd

enum Dimensions {
    /// Cardboard delivery box (w, h, d).
    static let box = SIMD3<Float>(0.5, 0.32, 0.4)
}

struct Rect {
    var minX: Float, minZ: Float, maxX: Float, maxZ: Float

    init(minX: Float, minZ: Float, maxX: Float, maxZ: Float) {
        self.minX = minX; self.minZ = minZ; self.maxX = maxX; self.maxZ = maxZ
    }

    init(center: SIMD2<Float>, size: SIMD2<Float>) {
        minX = center.x - size.x / 2; maxX = center.x + size.x / 2
        minZ = center.y - size.y / 2; maxZ = center.y + size.y / 2
    }

    func expanded(_ m: Float) -> Rect { Rect(minX: minX - m, minZ: minZ - m, maxX: maxX + m, maxZ: maxZ + m) }
    func contains(_ p: SIMD2<Float>) -> Bool { p.x >= minX && p.x <= maxX && p.y >= minZ && p.y <= maxZ }
    var center: SIMD2<Float> { SIMD2((minX + maxX) / 2, (minZ + maxZ) / 2) }
    var size: SIMD2<Float> { SIMD2(maxX - minX, maxZ - minZ) }
}

struct FixtureSpec {
    let kind: FixtureKind
    let center: SIMD2<Float>   // x, z
    let normal: SIMD2<Float>   // direction the open side faces
    let length: Float
    var depth: Float { kind == .shelf ? 0.5 : 0.7 }
    var height: Float { kind == .shelf ? 1.8 : 2.0 }
    var levelHeights: [Float] { kind == .shelf ? [0.1, 0.68, 1.26] : [0.14, 0.74, 1.34] }

    var rect: Rect {
        abs(normal.x) > 0.5
            ? Rect(center: center, size: SIMD2(depth, length))
            : Rect(center: center, size: SIMD2(length, depth))
    }
}

/// Where everything goes in a store. All positions are x,z on the floor.
struct StoreLayout {
    let width: Float
    let depth: Float
    let fixtures: [FixtureSpec]
    let wallThickness: Float = 0.2
    let doorMinX: Float
    let doorMaxX: Float
    let counter: Rect
    let cashierArea: Rect
    let payPoint: SIMD2<Float>
    let desk: Rect
    let pad: Rect
    let bin: Rect
    let spawnPoint: SIMD2<Float>
    let exitPoint: SIMD2<Float>
    let doorInside: SIMD2<Float>
    let playerStart: SIMD2<Float>

    var doorCenterX: Float { (doorMinX + doorMaxX) / 2 }

    init(level: StoreLevel) {
        let W = level.width, D = level.depth
        width = W; depth = D
        let frontStart = D - 7.0
        let unitLen: Float = 2.0
        var specs: [FixtureSpec] = []

        func kinds(_ list: [FixtureKind]?, _ i: Int) -> FixtureKind? {
            guard let list = list, !list.isEmpty else { return nil }
            return list[i % list.count]
        }

        // Rows along the side walls and middle run between zStart and zEnd.
        let zStart: Float = 2.6
        let zEnd: Float = frontStart - 0.5
        let rowCount = max(1, Int((zEnd - zStart) / unitLen))
        let rowOffset = zStart + ((zEnd - zStart) - Float(rowCount) * unitLen) / 2

        // Back wall
        if level.backWall != nil {
            let count = max(1, Int((W - 1.6) / unitLen))
            let x0 = (W - Float(count) * unitLen) / 2
            for i in 0..<count {
                let k = kinds(level.backWall, i)!
                let d: Float = k == .shelf ? 0.5 : 0.7
                specs.append(FixtureSpec(kind: k, center: SIMD2(x0 + (Float(i) + 0.5) * unitLen, d / 2 + 0.05),
                                         normal: SIMD2(0, 1), length: unitLen))
            }
        }
        // Left wall
        if level.leftWall != nil {
            for i in 0..<rowCount {
                let k = kinds(level.leftWall, i)!
                let d: Float = k == .shelf ? 0.5 : 0.7
                specs.append(FixtureSpec(kind: k, center: SIMD2(d / 2 + 0.05, rowOffset + (Float(i) + 0.5) * unitLen),
                                         normal: SIMD2(1, 0), length: unitLen))
            }
        }
        // Right wall
        if level.rightWall != nil {
            for i in 0..<rowCount {
                let k = kinds(level.rightWall, i)!
                let d: Float = k == .shelf ? 0.5 : 0.7
                specs.append(FixtureSpec(kind: k, center: SIMD2(W - d / 2 - 0.05, rowOffset + (Float(i) + 0.5) * unitLen),
                                         normal: SIMD2(-1, 0), length: unitLen))
            }
        }
        // Middle gondolas: double-sided columns 1 m wide with 2 m aisles.
        let leftClear: Float = 0.75 + 2.0
        let avail = (W - leftClear) - leftClear
        let columns = max(0, min(level.maxGondolaColumns, Int((avail + 2.0) / 3.0)))
        if columns > 0 {
            let total = Float(columns) + Float(columns - 1) * 2.0
            let startX = leftClear + (avail - total) / 2
            for c in 0..<columns {
                let x0 = startX + Float(c) * 3.0
                for i in 0..<rowCount {
                    let z = rowOffset + (Float(i) + 0.5) * unitLen
                    specs.append(FixtureSpec(kind: .shelf, center: SIMD2(x0 + 0.25, z), normal: SIMD2(-1, 0), length: unitLen))
                    specs.append(FixtureSpec(kind: .shelf, center: SIMD2(x0 + 0.75, z), normal: SIMD2(1, 0), length: unitLen))
                }
            }
        }
        fixtures = specs

        doorMinX = W - 4.0
        doorMaxX = W - 2.0
        counter = Rect(minX: 2.55, minZ: D - 4.2, maxX: 3.45, maxZ: D - 1.8)
        cashierArea = Rect(minX: 0.3, minZ: D - 4.6, maxX: 2.55, maxZ: D - 0.5)
        payPoint = SIMD2(4.15, D - 3.0)
        desk = Rect(minX: 0.2, minZ: D - 6.9, maxX: 0.9, maxZ: D - 5.7)
        pad = Rect(minX: W - 2.1, minZ: D - 6.6, maxX: W - 0.3, maxZ: D - 4.0)
        bin = Rect(minX: W - 1.0, minZ: D - 1.2, maxX: W - 0.3, maxZ: D - 0.5)
        spawnPoint = SIMD2(W - 3.0, D + 3.5)
        exitPoint = SIMD2(W - 3.0, D + 4.2)
        doorInside = SIMD2(W - 3.0, D - 1.2)
        playerStart = SIMD2(1.6, D - 3.0)
    }

    /// Queue spot k (0 = paying customer). Runs back into the store, then snakes.
    func queueSpot(_ k: Int) -> SIMD2<Float> {
        let perColumn = 5
        let col = k / perColumn
        let row = k % perColumn
        let x = payPoint.x + Float(col) * 0.9
        let z = col % 2 == 0 ? payPoint.y - Float(row) * 0.8 : payPoint.y - Float(perColumn - 1 - row) * 0.8
        return SIMD2(x, z)
    }

    /// Pad drop position for the n-th box (2 columns x 4 rows, stacked up to 5 high).
    func padPosition(_ n: Int) -> SIMD3<Float> {
        let perLayer = 8
        let layer = n / perLayer
        let i = n % perLayer
        let col = i % 2, row = i / 2
        let x = pad.minX + 0.4 + Float(col) * 0.95
        let z = pad.minZ + 0.35 + Float(row) * 0.6
        return SIMD3(x, Float(layer) * Dimensions.box.y, z)
    }
    static let padCapacity = 40

    /// Solid obstacles for the player (and the basis for customer navigation).
    var solidRects: [Rect] {
        var r = fixtures.map { $0.rect }
        r.append(counter)
        r.append(desk)
        r.append(bin)
        let t = wallThickness
        r.append(Rect(minX: -t, minZ: -t, maxX: width + t, maxZ: 0))                 // back
        r.append(Rect(minX: -t, minZ: -t, maxX: 0, maxZ: depth + t))                 // left
        r.append(Rect(minX: width, minZ: -t, maxX: width + t, maxZ: depth + t))      // right
        r.append(Rect(minX: -t, minZ: depth, maxX: doorMinX, maxZ: depth + t))       // front left of door
        r.append(Rect(minX: doorMaxX, minZ: depth, maxX: width + t, maxZ: depth + t)) // front right of door
        return r
    }

    /// Keeps the player inside the store.
    var playerOnlyRects: [Rect] {
        [Rect(minX: doorMinX, minZ: depth - 0.05, maxX: doorMaxX, maxZ: depth + 1)]
    }
}

/// Grid-based navigation for customers using GameplayKit A*.
final class NavGrid {
    let cell: Float = 0.5
    let cols: Int
    let rows: Int
    private var blocked: [Bool]
    private let graph: GKGridGraph<GKGridGraphNode>

    init(layout: StoreLayout) {
        cols = Int(ceil(layout.width / cell))
        rows = Int(ceil((layout.depth + 5) / cell))
        blocked = Array(repeating: false, count: cols * rows)
        graph = GKGridGraph<GKGridGraphNode>(fromGridStartingAt: vector_int2(0, 0), width: Int32(cols), height: Int32(rows), diagonalsAllowed: true)

        var obstacles = layout.fixtures.map { $0.rect.expanded(0.28) }
        obstacles.append(layout.counter.expanded(0.28))
        obstacles.append(layout.desk.expanded(0.28))
        obstacles.append(layout.bin.expanded(0.28))
        obstacles.append(layout.pad.expanded(0.2))
        obstacles.append(layout.cashierArea)
        for c in 0..<cols {
            for r in 0..<rows {
                let p = center(c, r)
                var b = false
                if p.x < 0.3 || p.x > layout.width - 0.3 || p.y < 0.3 { b = true }
                // Front wall line and outside: only the door corridor is walkable.
                if p.y > layout.depth - 0.3 {
                    if p.x < layout.doorMinX + 0.3 || p.x > layout.doorMaxX - 0.3 { b = true }
                }
                if !b { for o in obstacles where o.contains(p) { b = true; break } }
                blocked[r * cols + c] = b
            }
        }
        var toRemove: [GKGraphNode] = []
        for c in 0..<cols {
            for r in 0..<rows where blocked[r * cols + c] {
                if let n = graph.node(atGridPosition: vector_int2(Int32(c), Int32(r))) { toRemove.append(n) }
            }
        }
        graph.remove(toRemove)
    }

    func center(_ c: Int, _ r: Int) -> SIMD2<Float> {
        SIMD2((Float(c) + 0.5) * cell, (Float(r) + 0.5) * cell)
    }

    func cellOf(_ p: SIMD2<Float>) -> (Int, Int) {
        (max(0, min(cols - 1, Int(p.x / cell))), max(0, min(rows - 1, Int(p.y / cell))))
    }

    func isBlocked(_ p: SIMD2<Float>) -> Bool {
        let c = Int(floor(p.x / cell)), r = Int(floor(p.y / cell))
        if c < 0 || r < 0 || c >= cols || r >= rows { return true }
        return blocked[r * cols + c]
    }

    func nearestFree(_ p: SIMD2<Float>) -> (Int, Int) {
        let (c0, r0) = cellOf(p)
        if !blocked[r0 * cols + c0] { return (c0, r0) }
        for radius in 1...8 {
            var best: (Int, Int)?
            var bestD = Float.greatestFiniteMagnitude
            for dc in -radius...radius {
                for dr in -radius...radius where abs(dc) == radius || abs(dr) == radius {
                    let c = c0 + dc, r = r0 + dr
                    if c < 0 || r < 0 || c >= cols || r >= rows || blocked[r * cols + c] { continue }
                    let d = simd_distance(center(c, r), p)
                    if d < bestD { bestD = d; best = (c, r) }
                }
            }
            if let b = best { return b }
        }
        return (c0, r0)
    }

    /// Path from a to b as world points (ending exactly at b), smoothed with line-of-sight checks.
    func path(from a: SIMD2<Float>, to b: SIMD2<Float>) -> [SIMD2<Float>] {
        let (ac, ar) = nearestFree(a)
        let (bc, br) = nearestFree(b)
        guard let start = graph.node(atGridPosition: vector_int2(Int32(ac), Int32(ar))),
              let end = graph.node(atGridPosition: vector_int2(Int32(bc), Int32(br))) else { return [b] }
        let nodes = graph.findPath(from: start, to: end).compactMap { $0 as? GKGridGraphNode }
        if nodes.isEmpty { return [b] }
        var pts = nodes.map { center(Int($0.gridPosition.x), Int($0.gridPosition.y)) }
        pts.append(b)
        // String-pulling
        var out: [SIMD2<Float>] = []
        var anchor = a
        var i = 0
        while i < pts.count {
            var j = pts.count - 1
            while j > i && !clear(anchor, pts[j]) { j -= 1 }
            out.append(pts[j])
            anchor = pts[j]
            i = j + 1
        }
        return out
    }

    func clear(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Bool {
        let d = simd_distance(a, b)
        let steps = max(1, Int(d / 0.2))
        for s in 1..<steps {
            let p = a + (b - a) * (Float(s) / Float(steps))
            if isBlocked(p) { return false }
        }
        return true
    }
}
