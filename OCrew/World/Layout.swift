import Foundation
import simd

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

/// Store floor plan, grown until the requested fixtures fit.
struct StoreLayout {
    let width: Float
    let depth: Float
    let fixtures: [FixtureSpec]
    let wallThickness: Float = 0.2
    let doorMinX: Float
    let doorMaxX: Float
    let bin: Rect
    let playerStart: SIMD2<Float>

    static let unitLen: Float = 2.0
    static let frontArea: Float = 3.5

    /// Picks the smallest store (from a minimum size) that fits the fixtures.
    static func fit(cold: [FixtureKind], shelves: Int, minWidth: Float = 9, minDepth: Float = 11) -> StoreLayout {
        var w: Float = minWidth, d: Float = minDepth
        for step in 0..<40 {
            if let l = StoreLayout(width: w, depth: d, cold: cold, shelves: shelves) { return l }
            if step % 2 == 0 { d += 1 } else { w += 1 }
        }
        return StoreLayout(width: w, depth: d, cold: cold, shelves: shelves)
            ?? StoreLayout(width: 30, depth: 30, cold: [], shelves: 1)!
    }

    init?(width W: Float, depth D: Float, cold: [FixtureKind], shelves: Int) {
        width = W; depth = D
        let L = StoreLayout.unitLen
        let zStart: Float = 2.6
        let zEnd = D - StoreLayout.frontArea
        let rowCount = Int((zEnd - zStart) / L)
        if rowCount < 1 { return nil }
        let rowOffset = zStart + ((zEnd - zStart) - Float(rowCount) * L) / 2
        func rowZ(_ i: Int) -> Float { rowOffset + (Float(i) + 0.5) * L }

        // Candidate positions
        var left: [(SIMD2<Float>, SIMD2<Float>)] = []      // (x offset handled per kind), normal
        var right: [(SIMD2<Float>, SIMD2<Float>)] = []
        for i in 0..<rowCount {
            left.append((SIMD2(0, rowZ(i)), SIMD2(1, 0)))
            right.append((SIMD2(W, rowZ(i)), SIMD2(-1, 0)))
        }
        var back: [SIMD2<Float>] = []
        let backCount = max(0, Int((W - 1.8) / L))
        let bx0 = (W - Float(backCount) * L) / 2
        for i in 0..<backCount { back.append(SIMD2(bx0 + (Float(i) + 0.5) * L, 0)) }
        var gondolas: [(SIMD2<Float>, SIMD2<Float>)] = []
        let leftClear: Float = 0.75 + 2.0
        let avail = (W - leftClear) - leftClear
        let columns = max(0, Int((avail + 2.0) / 3.0))
        if columns > 0 {
            let total = Float(columns) + Float(columns - 1) * 2.0
            let startX = leftClear + (avail - total) / 2
            for c in 0..<columns {
                let x0 = startX + Float(c) * 3.0
                for i in 0..<rowCount {
                    gondolas.append((SIMD2(x0 + 0.25, rowZ(i)), SIMD2(-1, 0)))
                    gondolas.append((SIMD2(x0 + 0.75, rowZ(i)), SIMD2(1, 0)))
                }
            }
        }

        var specs: [FixtureSpec] = []
        func wallSpec(_ kind: FixtureKind, _ p: (SIMD2<Float>, SIMD2<Float>)) -> FixtureSpec {
            let d: Float = kind == .shelf ? 0.5 : 0.7
            let x = p.1.x > 0 ? d / 2 + 0.05 : W - d / 2 - 0.05
            return FixtureSpec(kind: kind, center: SIMD2(x, p.0.y), normal: p.1, length: L)
        }
        // Cold units on the left wall first, then the right wall.
        var coldQueue = cold
        while !coldQueue.isEmpty && !left.isEmpty { specs.append(wallSpec(coldQueue.removeFirst(), left.removeFirst())) }
        while !coldQueue.isEmpty && !right.isEmpty { specs.append(wallSpec(coldQueue.removeFirst(), right.removeFirst())) }
        if !coldQueue.isEmpty { return nil }
        // Shelves: back wall, middle gondolas, then remaining wall space.
        var need = shelves
        while need > 0 && !back.isEmpty {
            let p = back.removeFirst()
            specs.append(FixtureSpec(kind: .shelf, center: SIMD2(p.x, 0.3), normal: SIMD2(0, 1), length: L))
            need -= 1
        }
        while need > 0 && !gondolas.isEmpty {
            let p = gondolas.removeFirst()
            specs.append(FixtureSpec(kind: .shelf, center: p.0, normal: p.1, length: L))
            need -= 1
        }
        while need > 0 && !left.isEmpty { specs.append(wallSpec(.shelf, left.removeFirst())); need -= 1 }
        while need > 0 && !right.isEmpty { specs.append(wallSpec(.shelf, right.removeFirst())); need -= 1 }
        if need > 0 { return nil }
        fixtures = specs

        doorMinX = W / 2 - 1
        doorMaxX = W / 2 + 1
        bin = Rect(minX: 0.3, minZ: D - 1.2, maxX: 1.0, maxZ: D - 0.5)
        playerStart = SIMD2(W / 2, D - 1.6)
    }

    var solidRects: [Rect] {
        var r = fixtures.map { $0.rect }
        r.append(bin)
        let t = wallThickness
        r.append(Rect(minX: -t, minZ: -t, maxX: width + t, maxZ: 0))
        r.append(Rect(minX: -t, minZ: -t, maxX: 0, maxZ: depth + t))
        r.append(Rect(minX: width, minZ: -t, maxX: width + t, maxZ: depth + t))
        r.append(Rect(minX: -t, minZ: depth, maxX: width + t, maxZ: depth + t))   // door is closed while you sort
        return r
    }

    /// True if a floor point is open (not inside fixtures/walls) with the given clearance.
    func isOpen(_ p: SIMD2<Float>, clearance: Float) -> Bool {
        if p.x < clearance || p.x > width - clearance || p.y < clearance || p.y > depth - clearance { return false }
        for r in solidRects where r.expanded(clearance).contains(p) { return false }
        return true
    }
}
