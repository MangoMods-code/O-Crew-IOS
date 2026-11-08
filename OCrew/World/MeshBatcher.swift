import SceneKit
import simd

/// Merges many product models into ONE geometry with one draw call per material.
/// Reads the raw triangles out of SceneKit's primitives itself, so it doesn't depend on
/// `flattenedClone()` (which came out empty for product meshes).
@MainActor
final class MeshBatcher {
    private struct Part {
        let positions: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        let uvs: [SIMD2<Float>]
        let elements: [(indices: [UInt32], material: SCNMaterial)]
    }

    private struct Bucket {
        var material: SCNMaterial
        var indices: [UInt32] = []
    }

    private static var partCache: [ObjectIdentifier: Part] = [:]

    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var uvs: [SIMD2<Float>] = []
    private var buckets: [ObjectIdentifier: Bucket] = [:]
    private var order: [ObjectIdentifier] = []
    private(set) var failed = false

    var isEmpty: Bool { positions.isEmpty }

    /// Adds every geometry in `template` (one level of children + itself), placed by `transform`.
    func add(_ template: SCNNode, transform: simd_float4x4) {
        var nodes: [SCNNode] = [template]
        nodes.append(contentsOf: template.childNodes)
        for n in nodes {
            guard let g = n.geometry else { continue }
            let local = n === template ? matrix_identity_float4x4 : n.simdTransform
            guard let part = Self.part(for: g) else { failed = true; continue }
            append(part, transform: transform * local)
        }
    }

    private func append(_ p: Part, transform m: simd_float4x4) {
        let base = UInt32(positions.count)
        let r = simd_float3x3(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                              SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                              SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
        positions.reserveCapacity(positions.count + p.positions.count)
        for v in p.positions {
            let w = m * SIMD4(v, 1)
            positions.append(SIMD3(w.x, w.y, w.z))
        }
        for nrm in p.normals {
            let t = r * nrm
            let len = simd_length(t)
            normals.append(len > 0 ? t / len : SIMD3(0, 1, 0))
        }
        uvs.append(contentsOf: p.uvs)
        for e in p.elements {
            let key = ObjectIdentifier(e.material)
            if buckets[key] == nil {
                buckets[key] = Bucket(material: e.material)
                order.append(key)
            }
            buckets[key]!.indices.append(contentsOf: e.indices.map { $0 + base })
        }
    }

    /// The merged node, or nil if nothing was added / something couldn't be read.
    func build() -> SCNNode? {
        guard !positions.isEmpty, !failed else { return nil }
        let vData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let nData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let tData = uvs.withUnsafeBufferPointer { Data(buffer: $0) }
        let v3 = MemoryLayout<SIMD3<Float>>.stride
        let v2 = MemoryLayout<SIMD2<Float>>.stride
        let vs = SCNGeometrySource(data: vData, semantic: .vertex, vectorCount: positions.count, usesFloatComponents: true,
                                   componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: v3)
        let ns = SCNGeometrySource(data: nData, semantic: .normal, vectorCount: normals.count, usesFloatComponents: true,
                                   componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: v3)
        let ts = SCNGeometrySource(data: tData, semantic: .texcoord, vectorCount: uvs.count, usesFloatComponents: true,
                                   componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: v2)
        var elements: [SCNGeometryElement] = []
        var materials: [SCNMaterial] = []
        for k in order {
            guard let b = buckets[k], !b.indices.isEmpty else { continue }
            elements.append(SCNGeometryElement(indices: b.indices, primitiveType: .triangles))
            materials.append(b.material)
        }
        let g = SCNGeometry(sources: [vs, ns, ts], elements: elements)
        g.materials = materials
        return SCNNode(geometry: g)
    }

    // MARK: Reading SceneKit geometry

    private static func part(for g: SCNGeometry) -> Part? {
        let key = ObjectIdentifier(g)
        if let p = partCache[key] { return p }
        guard let vs = g.sources(for: .vertex).first, let pos = readVec3(vs) else { return nil }
        var nrm = g.sources(for: .normal).first.flatMap { readVec3($0) } ?? []
        if nrm.count != pos.count { nrm = Array(repeating: SIMD3(0, 1, 0), count: pos.count) }
        var uv = g.sources(for: .texcoord).first.flatMap { readVec2($0) } ?? []
        if uv.count != pos.count { uv = Array(repeating: SIMD2(0, 0), count: pos.count) }
        let mats = g.materials.isEmpty ? [SCNMaterial()] : g.materials
        var els: [(indices: [UInt32], material: SCNMaterial)] = []
        for (i, e) in g.elements.enumerated() {
            guard let idx = readIndices(e) else { return nil }
            els.append((idx, mats[i % mats.count]))
        }
        let p = Part(positions: pos, normals: nrm, uvs: uv, elements: els)
        partCache[key] = p
        return p
    }

    private static func component(_ raw: UnsafeRawBufferPointer, _ offset: Int, _ bytes: Int) -> Float {
        bytes == 8 ? Float(raw.loadUnaligned(fromByteOffset: offset, as: Double.self))
                   : raw.loadUnaligned(fromByteOffset: offset, as: Float.self)
    }

    private static func readVec3(_ s: SCNGeometrySource) -> [SIMD3<Float>]? {
        guard s.usesFloatComponents, s.componentsPerVector >= 3, s.bytesPerComponent == 4 || s.bytesPerComponent == 8 else { return nil }
        let b = s.bytesPerComponent
        return s.data.withUnsafeBytes { raw -> [SIMD3<Float>]? in
            var out: [SIMD3<Float>] = []
            out.reserveCapacity(s.vectorCount)
            for i in 0..<s.vectorCount {
                let o = s.dataOffset + i * s.dataStride
                guard o + 3 * b <= raw.count else { return nil }
                out.append(SIMD3(component(raw, o, b), component(raw, o + b, b), component(raw, o + 2 * b, b)))
            }
            return out
        }
    }

    private static func readVec2(_ s: SCNGeometrySource) -> [SIMD2<Float>]? {
        guard s.usesFloatComponents, s.componentsPerVector >= 2, s.bytesPerComponent == 4 || s.bytesPerComponent == 8 else { return nil }
        let b = s.bytesPerComponent
        return s.data.withUnsafeBytes { raw -> [SIMD2<Float>]? in
            var out: [SIMD2<Float>] = []
            out.reserveCapacity(s.vectorCount)
            for i in 0..<s.vectorCount {
                let o = s.dataOffset + i * s.dataStride
                guard o + 2 * b <= raw.count else { return nil }
                out.append(SIMD2(component(raw, o, b), component(raw, o + b, b)))
            }
            return out
        }
    }

    private static func readIndices(_ e: SCNGeometryElement) -> [UInt32]? {
        let bpi = e.bytesPerIndex
        guard bpi == 1 || bpi == 2 || bpi == 4 else { return nil }
        let raw: [UInt32] = e.data.withUnsafeBytes { buf in
            let n = buf.count / bpi
            var out = [UInt32](repeating: 0, count: n)
            for i in 0..<n {
                switch bpi {
                case 1: out[i] = UInt32(buf.loadUnaligned(fromByteOffset: i, as: UInt8.self))
                case 2: out[i] = UInt32(buf.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self))
                default: out[i] = buf.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)
                }
            }
            return out
        }
        switch e.primitiveType {
        case .triangles:
            let count = min(raw.count, e.primitiveCount * 3)
            return Array(raw.prefix(count))
        case .triangleStrip:
            guard raw.count >= 3 else { return [] }
            var out: [UInt32] = []
            for i in 0..<(raw.count - 2) {
                let a = raw[i], b = raw[i + 1], c = raw[i + 2]
                if a == b || b == c || a == c { continue }
                if i % 2 == 0 { out += [a, b, c] } else { out += [b, a, c] }
            }
            return out
        default:
            return nil
        }
    }
}
