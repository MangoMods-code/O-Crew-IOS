import SceneKit
import UIKit
import Metal
import simd

/// Renders each product's 3D model into a little "product photo" for the UI.
@MainActor
enum ProductIcons {
    private static var cache: [String: UIImage] = [:]
    private static var renderer: SCNRenderer?
    private static let scene = SCNScene()
    private static let holder = SCNNode()
    private static let camera = SCNNode()

    private static func setUp() -> SCNRenderer? {
        if let r = renderer { return r }
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let r = SCNRenderer(device: device, options: nil)
        scene.background.contents = UIColor(hex: 0xEEF0F2)
        scene.rootNode.addChildNode(holder)
        let cam = SCNCamera()
        cam.fieldOfView = 26
        cam.zNear = 0.01
        cam.zFar = 20
        camera.camera = cam
        scene.rootNode.addChildNode(camera)
        let key = SCNNode(); key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 900
        key.eulerAngles = SCNVector3(Float(-0.7), Float(0.6), Float(0))
        scene.rootNode.addChildNode(key)
        let fill = SCNNode(); fill.light = SCNLight()
        fill.light!.type = .directional
        fill.light!.intensity = 350
        fill.eulerAngles = SCNVector3(Float(-0.2), Float(-2.2), Float(0))
        scene.rootNode.addChildNode(fill)
        let amb = SCNNode(); amb.light = SCNLight()
        amb.light!.type = .ambient
        amb.light!.intensity = 420
        scene.rootNode.addChildNode(amb)
        r.scene = scene
        r.pointOfView = camera
        renderer = r
        return r
    }

    static func icon(for p: Product, expired: Bool = false) -> UIImage {
        let key = (expired ? "x:" : "") + p.id
        if let i = cache[key] { return i }
        guard let r = setUp() else { return Packaging.front(p) }
        holder.childNodes.forEach { $0.removeFromParentNode() }
        let n = ProductMesh.of(p, expired: expired).node()
        let s = p.shape.size
        let flat = ProductMesh.isFlat(p)
        // Flat packs are shown tilted up so you see the art on top.
        if flat { n.eulerAngles.x = Float.pi / 2 * 0.75 }
        holder.addChildNode(n)
        let height = flat ? max(s.d, s.h) : s.h
        let size = max(s.w, height, s.d * 0.6)
        let center = SIMD3<Float>(0, s.h / 2, 0)
        let dist = size / (2 * tan(13 * Float.pi / 180)) * 1.15
        camera.simdPosition = center + simd_normalize(SIMD3<Float>(0.32, 0.22, 1)) * dist
        camera.simdLook(at: center)
        let img = r.snapshot(atTime: 0, with: CGSize(width: 160, height: 160), antialiasingMode: .multisampling4X)
        holder.childNodes.forEach { $0.removeFromParentNode() }
        cache[key] = img
        return img
    }

    /// Renders icons ahead of time so the first pickup doesn't hitch.
    static func warm(_ ids: [String]) {
        for id in ids { if let p = Catalog.product(id) { _ = icon(for: p) } }
    }
}
