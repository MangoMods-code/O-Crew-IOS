import SceneKit
import UIKit

/// Builds every mesh in the game from primitives + generated textures (no external art needed).
@MainActor
enum Models {
    static let categoryWorld = 1
    static let categoryNoHit = 4

    private static var materialCache: [UInt32: SCNMaterial] = [:]
    private static var productTemplates: [String: SCNNode] = [:]
    private static var labelImages: [String: UIImage] = [:]
    private static var tagImages: [String: UIImage] = [:]

    // MARK: Materials

    static func mat(_ hex: UInt32) -> SCNMaterial {
        if let m = materialCache[hex] { return m }
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(hex: hex)
        m.lightingModel = .lambert
        materialCache[hex] = m
        return m
    }

    static func freshMat(_ hex: UInt32, alpha: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(hex: hex, alpha: alpha)
        m.lightingModel = .lambert
        if alpha < 1 { m.transparencyMode = .dualLayer; m.isDoubleSided = true }
        return m
    }

    static func imageMat(_ image: UIImage) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = image
        m.lightingModel = .lambert
        return m
    }

    static func emissive(_ hex: UInt32) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(hex: hex)
        m.emission.contents = UIColor(hex: hex)
        m.lightingModel = .constant
        return m
    }

    /// Invisible but hit-testable.
    static func invisible() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor.clear
        m.colorBufferWriteMask = []
        m.writesToDepthBuffer = false
        return m
    }

    static func setCategory(_ node: SCNNode, _ mask: Int) {
        node.categoryBitMask = mask
        for c in node.childNodes { setCategory(c, mask) }
    }

    // MARK: Primitives

    static func box(_ w: Float, _ h: Float, _ d: Float, _ hex: UInt32, chamfer: CGFloat = 0) -> SCNNode {
        let g = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: chamfer)
        g.firstMaterial = mat(hex)
        return SCNNode(geometry: g)
    }

    // MARK: Generated textures

    /// Packaging art: base color, accent band, a little logo blob and a white stripe.
    static func labelImage(for p: Product) -> UIImage {
        if let img = labelImages[p.id] { return img }
        let size = CGSize(width: 64, height: 64)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            UIColor(hex: p.color).setFill(); c.fill(CGRect(origin: .zero, size: size))
            UIColor(hex: p.accent).setFill(); c.fill(CGRect(x: 0, y: 22, width: 64, height: 22))
            UIColor.white.withAlphaComponent(0.85).setFill(); c.fill(CGRect(x: 0, y: 46, width: 64, height: 4))
            UIColor(hex: p.color).setFill(); c.fillEllipse(in: CGRect(x: 22, y: 25, width: 20, height: 16))
            UIColor.white.withAlphaComponent(0.7).setFill(); c.fillEllipse(in: CGRect(x: 27, y: 29, width: 10, height: 8))
            UIColor.black.withAlphaComponent(0.25).setFill(); c.fill(CGRect(x: 6, y: 54, width: 30, height: 3))
        }
        labelImages[p.id] = img
        return img
    }

    static func checkerImage(_ a: UInt32, _ b: UInt32, grout: UInt32) -> UIImage {
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            for i in 0..<2 {
                for j in 0..<2 {
                    UIColor(hex: (i + j) % 2 == 0 ? a : b).setFill()
                    c.fill(CGRect(x: i * 128, y: j * 128, width: 128, height: 128))
                }
            }
            UIColor(hex: grout).setFill()
            c.fill(CGRect(x: 0, y: 0, width: 256, height: 3))
            c.fill(CGRect(x: 0, y: 128, width: 256, height: 3))
            c.fill(CGRect(x: 0, y: 0, width: 3, height: 256))
            c.fill(CGRect(x: 128, y: 0, width: 3, height: 256))
        }
    }

    static func stripesImage(_ a: UInt32, _ b: UInt32) -> UIImage {
        let size = CGSize(width: 128, height: 128)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            UIColor(hex: a).setFill(); c.fill(CGRect(origin: .zero, size: size))
            UIColor(hex: b).setFill()
            for k in stride(from: -128, to: 256, by: 32) {
                c.move(to: CGPoint(x: k, y: 0)); c.addLine(to: CGPoint(x: k + 16, y: 0))
                c.addLine(to: CGPoint(x: k + 16 + 128, y: 128)); c.addLine(to: CGPoint(x: k + 128, y: 128))
                c.closePath(); c.fillPath()
            }
        }
    }

    static func textImage(_ text: String, size: CGSize, font: UIFont, color: UIColor, bg: UIColor, corner: CGFloat = 0) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            bg.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: corner).fill()
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
            let h = (text as NSString).boundingRect(with: size, options: .usesLineFragmentOrigin, attributes: attrs, context: nil).height
            (text as NSString).draw(in: CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h), withAttributes: attrs)
        }
    }

    static func priceTagImage(name: String, price: String) -> UIImage {
        let key = name + "|" + price
        if let img = tagImages[key] { return img }
        let size = CGSize(width: 256, height: 88)
        let img = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(hex: 0xFFF9D6).setFill(); UIRectFill(CGRect(origin: .zero, size: size))
            UIColor(hex: 0xE5322D).setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 256, height: 8))
            let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byTruncatingTail
            (name as NSString).draw(in: CGRect(x: 6, y: 12, width: 244, height: 26), withAttributes: [
                .font: UIFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: UIColor(hex: 0x333333), .paragraphStyle: para])
            (price as NSString).draw(in: CGRect(x: 6, y: 36, width: 244, height: 48), withAttributes: [
                .font: UIFont.systemFont(ofSize: 40, weight: .black), .foregroundColor: UIColor(hex: 0x111111), .paragraphStyle: para])
        }
        tagImages[key] = img
        return img
    }

    // MARK: Products

    /// A single unit of a product, origin at bottom-center, front facing +z.
    static func productTemplate(_ p: Product) -> SCNNode {
        if let n = productTemplates[p.id] { return n }
        let root = SCNNode()
        let label = imageMat(labelImage(for: p))
        let base = mat(p.color)
        let accent = mat(p.accent)
        switch p.shape {
        case let .box(w, h, d):
            let g = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: 0.004)
            g.materials = [label, base, label, base, base, base]
            let n = SCNNode(geometry: g); n.position.y = h / 2; root.addChildNode(n)
        case let .bag(w, h, d):
            let g = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: CGFloat(min(w, d) * 0.4))
            g.materials = [label, base, label, base, base, base]
            let n = SCNNode(geometry: g); n.position.y = h / 2; root.addChildNode(n)
        case let .carton(w, h, d):
            let g = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: 0.002)
            g.materials = [label, base, label, base, base, base]
            let n = SCNNode(geometry: g); n.position.y = h / 2; root.addChildNode(n)
            let roof = SCNPyramid(width: CGFloat(w), height: 0.04, length: CGFloat(d))
            roof.firstMaterial = base
            let r = SCNNode(geometry: roof); r.position.y = h; root.addChildNode(r)
        case let .can(r, h):
            let g = SCNCylinder(radius: CGFloat(r), height: CGFloat(h))
            g.radialSegmentCount = 16
            g.materials = [label, accent, base]
            let n = SCNNode(geometry: g); n.position.y = h / 2; root.addChildNode(n)
        case let .jar(r, h):
            let body = SCNCylinder(radius: CGFloat(r), height: CGFloat(h * 0.82))
            body.radialSegmentCount = 16
            body.materials = [label, base, base]
            let b = SCNNode(geometry: body); b.position.y = h * 0.41; root.addChildNode(b)
            let lid = SCNCylinder(radius: CGFloat(r * 1.04), height: CGFloat(h * 0.18))
            lid.radialSegmentCount = 16
            lid.firstMaterial = accent
            let l = SCNNode(geometry: lid); l.position.y = h * 0.91; root.addChildNode(l)
        case let .bottle(r, h):
            let body = SCNCylinder(radius: CGFloat(r), height: CGFloat(h * 0.68))
            body.radialSegmentCount = 14
            body.materials = [label, base, base]
            let b = SCNNode(geometry: body); b.position.y = h * 0.34; root.addChildNode(b)
            let shoulder = SCNCone(topRadius: CGFloat(r * 0.42), bottomRadius: CGFloat(r), height: CGFloat(h * 0.14))
            shoulder.radialSegmentCount = 14
            shoulder.firstMaterial = base
            let s = SCNNode(geometry: shoulder); s.position.y = h * 0.75; root.addChildNode(s)
            let neck = SCNCylinder(radius: CGFloat(r * 0.42), height: CGFloat(h * 0.11))
            neck.radialSegmentCount = 10
            neck.firstMaterial = base
            let nk = SCNNode(geometry: neck); nk.position.y = h * 0.875; root.addChildNode(nk)
            let cap = SCNCylinder(radius: CGFloat(r * 0.48), height: CGFloat(h * 0.07))
            cap.radialSegmentCount = 10
            cap.firstMaterial = accent
            let cp = SCNNode(geometry: cap); cp.position.y = h * 0.965; root.addChildNode(cp)
        }
        productTemplates[p.id] = root
        return root
    }

    static func productNode(_ p: Product, expired: Bool = false) -> SCNNode {
        expired ? expiredTemplate(p).clone() : productTemplate(p).clone()
    }

    private static var expiredTemplates: [String: SCNNode] = [:]

    /// Same product, but faded/brown with a red "expired" sticker.
    static func expiredTemplate(_ p: Product) -> SCNNode {
        if let n = expiredTemplates[p.id] { return n }
        let root = SCNNode()
        let tint = UIColor(hex: 0x9C8B6E)
        for child in productTemplate(p).childNodes {
            guard let g = child.geometry?.copy() as? SCNGeometry else { continue }
            g.materials = g.materials.map { m in
                let c = (m.copy() as? SCNMaterial) ?? SCNMaterial()
                c.multiply.contents = tint
                return c
            }
            let n = SCNNode(geometry: g)
            n.transform = child.transform
            root.addChildNode(n)
        }
        let s = p.shape.size
        let sticker = SCNNode(geometry: SCNBox(width: CGFloat(min(0.07, s.w * 0.6)), height: CGFloat(min(0.05, s.h * 0.4)),
                                               length: 0.004, chamferRadius: 0))
        sticker.geometry?.firstMaterial = emissive(0xE02424)
        sticker.position = SCNVector3(0, s.h * 0.55, s.d / 2 + 0.003)
        root.addChildNode(sticker)
        expiredTemplates[p.id] = root
        return root
    }

    // MARK: Store signage

    private static var signImages: [String: UIImage] = [:]

    static func signImage(_ text: String, lit: Bool) -> UIImage {
        let key = text + (lit ? "|1" : "|0")
        if let i = signImages[key] { return i }
        let size = CGSize(width: max(360, CGFloat(text.count) * 34), height: 120)
        let img = UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(hex: lit ? 0xFFD54A : 0x1B2631).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 22).fill()
            UIColor(hex: lit ? 0xFFFFFF : 0x4A5A6A).setStroke()
            let border = UIBezierPath(roundedRect: rect.insetBy(dx: 5, dy: 5), cornerRadius: 18)
            border.lineWidth = 6
            border.stroke()
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 60, weight: .black),
                .foregroundColor: lit ? UIColor(hex: 0x1B2631) : UIColor.white, .paragraphStyle: para]
            (text as NSString).draw(in: CGRect(x: 10, y: 24, width: size.width - 20, height: 80), withAttributes: attrs)
        }
        signImages[key] = img
        return img
    }

    static func rowLabelImage(_ text: String, lit: Bool) -> UIImage {
        let key = "row|" + text + (lit ? "|1" : "|0")
        if let i = signImages[key] { return i }
        let size = CGSize(width: 768, height: 44)
        let img = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(hex: lit ? 0xFFD54A : 0xF7F7F2).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            UIColor(hex: 0x1B2631).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 768, height: 4))
            let para = NSMutableParagraphStyle(); para.alignment = .center
            (text.uppercased() as NSString).draw(in: CGRect(x: 0, y: 6, width: 768, height: 36), withAttributes: [
                .font: UIFont.systemFont(ofSize: 28, weight: .heavy), .foregroundColor: UIColor(hex: 0x1B2631),
                .paragraphStyle: para, .kern: 4])
        }
        signImages[key] = img
        return img
    }

    static func shelfTagImage(_ name: String) -> UIImage {
        let key = "tag|" + name
        if let i = signImages[key] { return i }
        let size = CGSize(width: 300, height: 70)
        let img = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(hex: 0xFFFFFF).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10).fill()
            let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byTruncatingTail
            (name as NSString).draw(in: CGRect(x: 6, y: 18, width: 288, height: 36), withAttributes: [
                .font: UIFont.systemFont(ofSize: 26, weight: .bold), .foregroundColor: UIColor(hex: 0x222222), .paragraphStyle: para])
        }
        signImages[key] = img
        return img
    }

    // MARK: Cardboard box

    static let boxSize = SIMD3<Float>(0.5, 0.32, 0.4)

    static func cardboardBox(for p: Product) -> SCNNode {
        let s = boxSize
        let g = SCNBox(width: CGFloat(s.x), height: CGFloat(s.y), length: CGFloat(s.z), chamferRadius: 0.01)
        let card = mat(0xC49A6C)
        let side = imageMat(cardboardSide(for: p))
        let top = imageMat(cardboardTop())
        g.materials = [side, side, side, side, top, card]
        let n = SCNNode(geometry: g)
        n.position.y = s.y / 2
        let root = SCNNode()
        root.addChildNode(n)
        return root
    }

    private static var cardboardSides: [String: UIImage] = [:]
    private static var cardboardTopImage: UIImage?

    private static func cardboardSide(for p: Product) -> UIImage {
        if let i = cardboardSides[p.id] { return i }
        let size = CGSize(width: 128, height: 80)
        let label = labelImage(for: p)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(hex: 0xC49A6C).setFill(); ctx.cgContext.fill(CGRect(origin: .zero, size: size))
            UIColor(hex: 0xB0855A).setFill(); ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 128, height: 6))
            label.draw(in: CGRect(x: 40, y: 18, width: 48, height: 48))
            UIColor(hex: 0x6B4F33).setStroke()
            ctx.cgContext.setLineWidth(2)
            ctx.cgContext.stroke(CGRect(x: 39, y: 17, width: 50, height: 50))
        }
        cardboardSides[p.id] = img
        return img
    }

    private static func cardboardTop() -> UIImage {
        if let i = cardboardTopImage { return i }
        let size = CGSize(width: 128, height: 128)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(hex: 0xC9A06F).setFill(); ctx.cgContext.fill(CGRect(origin: .zero, size: size))
            UIColor(hex: 0xD9C7A3).setFill(); ctx.cgContext.fill(CGRect(x: 0, y: 54, width: 128, height: 20))
            UIColor(hex: 0x9C7A52).setFill(); ctx.cgContext.fill(CGRect(x: 0, y: 63, width: 128, height: 2))
        }
        cardboardTopImage = img
        return img
    }

    // MARK: Floating text (popups, signs)

    static func billboardText(_ text: String, color: UIColor, bg: UIColor, width: Float, height: Float, fontSize: CGFloat = 44) -> SCNNode {
        let px = CGSize(width: CGFloat(width) * 400, height: CGFloat(height) * 400)
        let img = textImage(text, size: px, font: .systemFont(ofSize: fontSize, weight: .heavy), color: color, bg: bg, corner: px.height * 0.3)
        let plane = SCNPlane(width: CGFloat(width), height: CGFloat(height))
        let m = SCNMaterial()
        m.diffuse.contents = img
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.readsFromDepthBuffer = false
        m.writesToDepthBuffer = false
        plane.firstMaterial = m
        let n = SCNNode(geometry: plane)
        n.constraints = [SCNBillboardConstraint()]
        n.renderingOrder = 100
        n.categoryBitMask = categoryNoHit
        return n
    }
}
