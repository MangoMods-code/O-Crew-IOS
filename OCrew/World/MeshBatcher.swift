import SceneKit
import simd

/// Merges many product meshes into ONE geometry with one draw call per material.
/// Works on our own generated vertices (see ProductMesh), so sizes are always exact.
@MainActor
final class MeshBatcher {
    private struct Bucket {
        var material: SCNMaterial
        var indices: [UInt32] = []
    }

    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var uvs: [SIMD2<Float>] = []
    private var buckets: [ObjectIdentifier: Bucket] = [:]
    private var order: [ObjectIdentifier] = []

    var isEmpty: Bool { positions.isEmpty }

    /// A mesh already placed in the world, ready to be stitched into a batch quickly.
    struct Baked {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var groups: [(material: SCNMaterial, indices: [UInt32])] = []
    }

    static func bake(_ mesh: ProductMesh, transform m: simd_float4x4) -> Baked {
        var out = Baked()
        let r = simd_float3x3(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                              SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                              SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
        for part in mesh.parts {
            let mat = mesh.materials[min(part.material, mesh.materials.count - 1)]
            let base = UInt32(out.positions.count)
            for v in part.positions {
                let w = m * SIMD4(v, 1)
                out.positions.append(SIMD3(w.x, w.y, w.z))
            }
            for n in part.normals {
                let t = r * n
                let len = simd_length(t)
                out.normals.append(len > 0 ? t / len : SIMD3(0, 1, 0))
            }
            out.uvs.append(contentsOf: part.uvs)
            out.groups.append((mat, part.indices.map { $0 + base }))
        }
        return out
    }

    func add(_ b: Baked) {
        let base = UInt32(positions.count)
        positions.append(contentsOf: b.positions)
        normals.append(contentsOf: b.normals)
        uvs.append(contentsOf: b.uvs)
        for g in b.groups {
            let key = ObjectIdentifier(g.material)
            if buckets[key] == nil {
                buckets[key] = Bucket(material: g.material)
                order.append(key)
            }
            if base == 0 {
                buckets[key]!.indices.append(contentsOf: g.indices)
            } else {
                buckets[key]!.indices.append(contentsOf: g.indices.map { $0 + base })
            }
        }
    }

    func add(_ mesh: ProductMesh, transform m: simd_float4x4) {
        add(Self.bake(mesh, transform: m))
    }

    func buildGeometry() -> SCNGeometry? {
        guard !positions.isEmpty else { return nil }
        let v3 = MemoryLayout<SIMD3<Float>>.stride
        let v2 = MemoryLayout<SIMD2<Float>>.stride
        let vData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let nData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let tData = uvs.withUnsafeBufferPointer { Data(buffer: $0) }
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
        return g
    }

    func build() -> SCNNode? {
        guard let g = buildGeometry() else { return nil }
        return SCNNode(geometry: g)
    }
}
