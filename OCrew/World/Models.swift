import SceneKit
import UIKit

/// Builds every mesh in the game from primitives + generated textures (no external art needed).
@MainActor
enum Models {
    static let categoryWorld = 1
    static let categoryNoHit = 4

    private static var materialCache: [UInt32: SCNMaterial] = [:]
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
    /// Packaging art for UI icons (square crop of the front label).
    static func labelImage(for p: Product) -> UIImage {
        if let img = labelImages[p.id] { return img }
        let full = Packaging.front(p)
        var out = full
        if let cg = full.cgImage {
            let w = cg.width, h = cg.height
            let side = min(w / (w > h * 3 / 2 ? 2 : 1), h)
            let x = (w > h * 3 / 2 ? w / 2 : w) / 2 - side / 2
            let y = (h - side) / 2
            if let crop = cg.cropping(to: CGRect(x: max(0, x), y: max(0, y), width: side, height: side)) {
                out = UIImage(cgImage: crop, scale: full.scale, orientation: .up)
            }
        }
        labelImages[p.id] = out
        return out
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

    static func template(_ p: Product, expired: Bool) -> ProductMesh {
        ProductMesh.of(p, expired: expired)
    }

    static func translate(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(x, y, z, 1)
        return m
    }

    static func rotate(_ angle: Float, _ axis: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: angle, axis: axis))
    }

    static func productNode(_ p: Product, expired: Bool = false) -> SCNNode {
        ProductMesh.of(p, expired: expired).node()
    }

    /// Merges a node tree into one mesh for speed. If SceneKit can't merge it, the original
    /// tree is returned so nothing ever goes invisible.
    static func merged(_ container: SCNNode) -> SCNNode {
        let flat = container.flattenedClone()
        let (mn, mx) = flat.boundingBox
        let hasSize = (mx.x - mn.x) + (mx.y - mn.y) + (mx.z - mn.z) > 0.001
        if let g = flat.geometry, !g.sources.isEmpty, !g.elements.isEmpty, hasSize { return flat }
        return container
    }

    // MARK: Store signage

    private static var signImages: [String: UIImage] = [:]

    /// Largest font (down to `minSize`) at which `text` fits in `width`.
    static func fit(_ text: String, width: CGFloat, start: CGFloat, minSize: CGFloat, weight: UIFont.Weight) -> UIFont {
        var size = start
        while size > minSize {
            let w = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight)]).width
            if w <= width { break }
            size -= 2
        }
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    /// Hanging aisle sign: section names with icons, plus a bar showing how much of the unit is stocked.
    static func sectionSign(_ cats: [String], done: Int, total: Int, lit: Bool) -> UIImage {
        let complete = total > 0 && done >= total
        let key = "sign|" + cats.joined(separator: ",") + "|\(done)/\(total)|\(lit)"
        if let i = signImages[key] { return i }
        let size = CGSize(width: 512, height: 150)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: f).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let bg: UInt32 = lit ? 0xFFD54A : (complete ? 0x1E8449 : 0x16202B)
            let ink: UIColor = lit ? UIColor(hex: 0x16202B) : .white
            UIColor(hex: bg).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 26).fill()
            UIColor(white: 1, alpha: lit ? 0.9 : 0.22).setStroke()
            let border = UIBezierPath(roundedRect: rect.insetBy(dx: 5, dy: 5), cornerRadius: 21)
            border.lineWidth = 5
            border.stroke()
            let para = NSMutableParagraphStyle(); para.alignment = .center
            // One line per section when there are several, so nothing is ever cut off.
            let lines = cats.map { "\(SectionStyle.icon($0)) \($0.uppercased())" }
            let lineH: CGFloat = lines.count == 1 ? 70 : (lines.count == 2 ? 48 : 34)
            let top = (108 - lineH * CGFloat(lines.count)) / 2 + 6
            for (i, line) in lines.prefix(3).enumerated() {
                let font = fit(line, width: 470, start: lineH * 0.82, minSize: 18, weight: .black)
                let y = top + CGFloat(i) * lineH + (lineH - font.lineHeight) / 2
                (line as NSString).draw(in: CGRect(x: 20, y: y, width: 472, height: font.lineHeight + 2),
                                        withAttributes: [.font: font, .foregroundColor: ink, .paragraphStyle: para])
            }
            // Stock bar
            let track = CGRect(x: 34, y: 118, width: 444, height: 14)
            UIColor(white: lit ? 0 : 1, alpha: 0.22).setFill()
            UIBezierPath(roundedRect: track, cornerRadius: 7).fill()
            if total > 0 && done > 0 {
                let w = max(14, track.width * CGFloat(done) / CGFloat(total))
                UIColor(hex: lit ? 0x16202B : (complete ? 0xFFFFFF : 0x58D68D)).setFill()
                UIBezierPath(roundedRect: CGRect(x: track.minX, y: track.minY, width: w, height: 14), cornerRadius: 7).fill()
            }
        }
        signImages[key] = img
        return img
    }

    /// The strip on a shelf edge naming its section, color-coded per section.
    static func rowLabelImage(_ cat: String?, lit: Bool) -> UIImage {
        let key = "row|" + (cat ?? "-") + (lit ? "|1" : "|0")
        if let i = signImages[key] { return i }
        let size = CGSize(width: 768, height: 48)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        let img = UIGraphicsImageRenderer(size: size, format: f).image { _ in
            let base: UInt32 = cat.map { SectionStyle.color($0) } ?? 0x7F8C8D
            UIColor(hex: lit ? 0xFFD54A : base).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            UIColor(white: 0, alpha: 0.18).setFill()
            UIRectFill(CGRect(x: 0, y: 43, width: 768, height: 5))
            guard let cat = cat else { return }
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let text = "\(SectionStyle.icon(cat))  \(cat.uppercased())"
            (text as NSString).draw(in: CGRect(x: 0, y: 5, width: 768, height: 40), withAttributes: [
                .font: UIFont.systemFont(ofSize: 30, weight: .heavy),
                .foregroundColor: lit ? UIColor(hex: 0x16202B) : UIColor.white,
                .paragraphStyle: para, .kern: 3])
        }
        signImages[key] = img
        return img
    }

    /// Cooler door glass: a faint tint with diagonal reflection streaks.
    static func glassImage(tint: UInt32) -> UIImage {
        let key = "glass|\(tint)"
        if let i = signImages[key] { return i }
        let size = CGSize(width: 256, height: 256)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(hex: tint, alpha: 0.07).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            c.setFillColor(UIColor(white: 1, alpha: 0.10).cgColor)
            for (x, w) in [(CGFloat(30), CGFloat(26)), (CGFloat(78), CGFloat(10)), (CGFloat(170), CGFloat(18))] {
                c.move(to: CGPoint(x: x, y: 256)); c.addLine(to: CGPoint(x: x + w, y: 256))
                c.addLine(to: CGPoint(x: x + w + 90, y: 0)); c.addLine(to: CGPoint(x: x + 90, y: 0))
                c.closePath(); c.fillPath()
            }
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
