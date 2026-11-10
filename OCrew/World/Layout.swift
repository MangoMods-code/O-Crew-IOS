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
    let height: Float = 3.3
    let fixtures: [FixtureSpec]
    let wallThickness: Float = 0.2
    let doorMinX: Float
    let doorMaxX: Float
    let bin: Rect
    let playerStart: SIMD2<Float>
    // Scenery in the front of the store (all solid).
    let counter: Rect
    let basketStack: Rect
    let pallet: Rect
    let plant: Rect
    let wetSign: Rect

    static let unitLen: Float = 2.0
    static let frontArea: Float = 3.5

    var props: [Rect] { [counter, basketStack, pallet, plant, wetSign] }

    /// Picks the smallest store (from a minimum size) that fits the fixtures.
    static func fit(cold: [FixtureKind], shelves: Int, minWidth: Float = 8, minDepth: Float = 10) -> StoreLayout {
        var w: Float = minWidth, d: Float = minDepth
        for step in 0..<60 {
            if let l = StoreLayout(width: w, depth: d, cold: cold, shelves: shelves) { return l }
            if step % 2 == 0 { d += 1 } else { w += 1 }
        }
        return StoreLayout(width: w, depth: d, cold: cold, shelves: shelves)
            ?? StoreLayout(width: 40, depth: 40, cold: [], shelves: 1)!
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

        var specs: [FixtureSpec] = []
        func wallSpec(_ kind: FixtureKind, left: Bool, row: Int) -> FixtureSpec {
            let d: Float = kind == .shelf ? 0.5 : 0.7
            let x = left ? d / 2 + 0.05 : W - d / 2 - 0.05
            return FixtureSpec(kind: kind, center: SIMD2(x, rowZ(row)), normal: SIMD2(left ? 1 : -1, 0), length: L)
        }
        // Cold units run along the left wall first, then the right wall.
        var leftFree = Array(0..<rowCount), rightFree = Array(0..<rowCount)
        for kind in cold {
            if !leftFree.isEmpty { specs.append(wallSpec(kind, left: true, row: leftFree.removeFirst())) }
            else if !rightFree.isEmpty { specs.append(wallSpec(kind, left: false, row: rightFree.removeFirst())) }
            else { return nil }
        }

        // Shelves: about half along the back wall, the rest as double-sided aisles in the middle,
        // so the place reads as a store with aisles rather than one long wall.
        let backCount = max(0, Int((W - 1.8) / L))
        let sideClear: Float = 0.75 + 2.0
        let avail = W - sideClear * 2
        let columns = max(0, Int((avail + 2.0) / 3.0))
        let pairCap = columns * rowCount
        var nb = min(backCount, shelves)
        if pairCap > 0 && shelves >= 3 { nb = min(backCount, max(1, shelves / 2)) }
        var rest = shelves - nb
        var pairs = min(pairCap, rest / 2)
        var singles = rest - pairs * 2
        // Not enough room elsewhere? Put more on the back wall, then give up.
        while singles > leftFree.count + rightFree.count && nb < backCount {
            nb += 1
            rest = shelves - nb
            pairs = min(pairCap, rest / 2)
            singles = rest - pairs * 2
        }
        if singles > leftFree.count + rightFree.count { return nil }

        let bx0 = (W - Float(nb) * L) / 2
        for i in 0..<nb {
            specs.append(FixtureSpec(kind: .shelf, center: SIMD2(bx0 + (Float(i) + 0.5) * L, 0.3), normal: SIMD2(0, 1), length: L))
        }
        if pairs > 0 {
            let usedCols = Int((Float(pairs) / Float(rowCount)).rounded(.up))
            let total = Float(usedCols) + Float(usedCols - 1) * 2.0
            let startX = (W - total) / 2
            var left = pairs
            for c in 0..<usedCols {
                let x0 = startX + Float(c) * 3.0
                for i in 0..<rowCount where left > 0 {
                    specs.append(FixtureSpec(kind: .shelf, center: SIMD2(x0 + 0.25, rowZ(i)), normal: SIMD2(-1, 0), length: L))
                    specs.append(FixtureSpec(kind: .shelf, center: SIMD2(x0 + 0.75, rowZ(i)), normal: SIMD2(1, 0), length: L))
                    left -= 1
                }
            }
        }
        for _ in 0..<singles {
            if !rightFree.isEmpty { specs.append(wallSpec(.shelf, left: false, row: rightFree.removeFirst())) }
            else { specs.append(wallSpec(.shelf, left: true, row: leftFree.removeFirst())) }
        }
        fixtures = specs

        doorMinX = W / 2 - 1
        doorMaxX = W / 2 + 1
        bin = Rect(minX: 0.3, minZ: D - 1.2, maxX: 1.0, maxZ: D - 0.5)
        playerStart = SIMD2(W / 2, D - 1.6)
        counter = Rect(minX: max(doorMaxX + 0.9, W - 2.9), minZ: D - 2.7, maxX: W - 0.6, maxZ: D - 2.0)
        basketStack = Rect(minX: doorMaxX + 0.35, minZ: D - 0.8, maxX: doorMaxX + 0.9, maxZ: D - 0.25)
        plant = Rect(minX: doorMinX - 0.75, minZ: D - 0.7, maxX: doorMinX - 0.3, maxZ: D - 0.25)
        pallet = Rect(minX: 1.25, minZ: D - 1.25, maxX: 2.15, maxZ: D - 0.35)
        wetSign = Rect(center: SIMD2(W / 2 - 1.4, D - 2.8), size: SIMD2(0.36, 0.36))
    }

    var solidRects: [Rect] {
        var r = fixtures.map { $0.rect }
        r.append(bin)
        r.append(contentsOf: props)
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
