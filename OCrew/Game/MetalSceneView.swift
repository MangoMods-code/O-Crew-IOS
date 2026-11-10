import UIKit
import SceneKit
import Metal
import QuartzCore

/// Renders the SceneKit scene ourselves, on the main thread, right after each game update.
/// One thread, one clock: no lock contention with SceneKit's render thread and no drift
/// between two separate frame timers.
final class MetalSceneView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    let device: MTLDevice
    let renderer: SCNRenderer
    private let queue: MTLCommandQueue
    private var depthTexture: MTLTexture?
    private var lastSize: CGSize = .zero
    var clearColor = MTLClearColor(red: 0.61, green: 0.79, blue: 0.92, alpha: 1)
    var renderScale: CGFloat = 2

    init?(scene: SCNScene, pointOfView: SCNNode) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        renderer = SCNRenderer(device: device, options: nil)
        super.init(frame: .zero)
        renderer.scene = scene
        renderer.pointOfView = pointOfView
        renderer.isPlaying = true
        renderer.autoenablesDefaultLighting = false
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm_srgb
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        metalLayer.maximumDrawableCount = 3
        isOpaque = true
        backgroundColor = .black
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = min(renderScale, window?.screen.scale ?? UIScreen.main.scale)
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    /// 1 = off, 2 or 4 = multisampled edges.
    var sampleCount = 4
    private var msaaTexture: MTLTexture?
    private var builtSamples = 0

    private func ensureTargets(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        if size == lastSize && depthTexture != nil && builtSamples == sampleCount { return }
        lastSize = size
        builtSamples = sampleCount
        var samples = sampleCount
        while samples > 1 && !device.supportsTextureSampleCount(samples) { samples /= 2 }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float_stencil8,
                                                         width: Int(size.width), height: Int(size.height), mipmapped: false)
        d.usage = .renderTarget
        if samples > 1 { d.textureType = .type2DMultisample; d.sampleCount = samples }
        #if targetEnvironment(simulator)
        d.storageMode = .private
        #else
        d.storageMode = .memoryless
        #endif
        depthTexture = device.makeTexture(descriptor: d)
        if depthTexture == nil {
            d.storageMode = .private
            depthTexture = device.makeTexture(descriptor: d)
        }
        msaaTexture = nil
        if samples > 1 {
            let c = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: metalLayer.pixelFormat,
                                                             width: Int(size.width), height: Int(size.height), mipmapped: false)
            c.usage = .renderTarget
            c.textureType = .type2DMultisample
            c.sampleCount = samples
            #if targetEnvironment(simulator)
            c.storageMode = .private
            #else
            c.storageMode = .memoryless
            #endif
            msaaTexture = device.makeTexture(descriptor: c)
            if msaaTexture == nil {
                c.storageMode = .private
                msaaTexture = device.makeTexture(descriptor: c)
            }
        }
    }

    /// Draws one frame at `time` (seconds).
    func render(time: TimeInterval) {
        let size = metalLayer.drawableSize
        guard size.width > 0, size.height > 0, let drawable = metalLayer.nextDrawable() else { return }
        ensureTargets(size)
        let pass = MTLRenderPassDescriptor()
        if let msaa = msaaTexture {
            pass.colorAttachments[0].texture = msaa
            pass.colorAttachments[0].resolveTexture = drawable.texture
            pass.colorAttachments[0].storeAction = .multisampleResolve
        } else {
            pass.colorAttachments[0].texture = drawable.texture
            pass.colorAttachments[0].storeAction = .store
        }
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = clearColor
        pass.depthAttachment.texture = depthTexture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        pass.stencilAttachment.texture = depthTexture
        pass.stencilAttachment.loadAction = .clear
        pass.stencilAttachment.storeAction = .dontCare
        guard let cb = queue.makeCommandBuffer() else { return }
        renderer.render(atTime: time, viewport: CGRect(origin: .zero, size: size), commandBuffer: cb, passDescriptor: pass)
        cb.present(drawable)
        cb.commit()
    }

    /// Converts a point in view coordinates to a world-space ray.
    func ray(at p: CGPoint) -> (SIMD3<Float>, SIMD3<Float>) {
        let s = Float(metalLayer.contentsScale)
        let a = renderer.unprojectPoint(SCNVector3(Float(p.x) * s, Float(p.y) * s, 0))
        let b = renderer.unprojectPoint(SCNVector3(Float(p.x) * s, Float(p.y) * s, 1))
        let o = SIMD3<Float>(a.x, a.y, a.z)
        return (o, SIMD3<Float>(b.x, b.y, b.z) - o)
    }
}
