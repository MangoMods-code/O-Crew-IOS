import SceneKit
import simd
import UIKit

/// Builds static scenery (walls, shelving, props) from our own vertices and merges it into one
/// node with one draw call per material.
@MainActor
final class MeshBuilder {
    private var parts: [ObjectIdentifier: MeshPart] = [:]
    private var mats: [ObjectIdentifier: SCNMaterial] = [:]
    private var order: [ObjectIdentifier] = []
    /// Applied to everything added while it is set (for rotated props).
    var transform = matrix_identity_float4x4

    private func edit(_ m: SCNMaterial, _ body: (inout MeshPart) -> Void) {
        let key = ObjectIdentifier(m)
        var part = parts[key] ?? MeshPart(material: 0)
        if mats[key] == nil { mats[key] = m; order.append(key) }
        let start = part.positions.count
        body(&part)
        if transform != matrix_identity_float4x4 {
            let t = transform
            let r = simd_float3x3(SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z),
                                  SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z),
                                  SIMD3(t.columns.2.x, t.columns.2.y, t.columns.2.z))
            for i in start..<part.positions.count {
                let w = t * SIMD4(part.positions[i], 1)
                part.positions[i] = SIMD3(w.x, w.y, w.z)
                part.normals[i] = simd_normalize(r * part.normals[i])
            }
        }
        parts[key] = part
    }

    /// A quad a→b→c→d (counter-clockwise seen from the front), with explicit UVs.
    func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, _ m: SCNMaterial,
              uv: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>) = (SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0))) {
        let n = simd_normalize(simd_cross(b - a, d - a))
        edit(m) { $0.quad(a, b, c, d, n: n, uv: uv) }
    }

    /// Axis-aligned box by center and size. `uvScale` > 0 tiles the texture that many times per meter.
    func box(_ cx: Float, _ cy: Float, _ cz: Float, _ w: Float, _ h: Float, _ d: Float, _ m: SCNMaterial, uvScale: Float = 0) {
        let x0 = cx - w / 2, x1 = cx + w / 2, y0 = cy - h / 2, y1 = cy + h / 2, z0 = cz - d / 2, z1 = cz + d / 2
        func uv(_ u: Float, _ v: Float) -> (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>) {
            uvScale > 0
                ? (SIMD2(0, v * uvScale), SIMD2(u * uvScale, v * uvScale), SIMD2(u * uvScale, 0), SIMD2(0, 0))
                : (SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0))
        }
        edit(m) { p in
            p.quad(SIMD3(x0, y0, z1), SIMD3(x1, y0, z1), SIMD3(x1, y1, z1), SIMD3(x0, y1, z1), n: SIMD3(0, 0, 1), uv: uv(w, h))
            p.quad(SIMD3(x1, y0, z0), SIMD3(x0, y0, z0), SIMD3(x0, y1, z0), SIMD3(x1, y1, z0), n: SIMD3(0, 0, -1), uv: uv(w, h))
            p.quad(SIMD3(x1, y0, z1), SIMD3(x1, y0, z0), SIMD3(x1, y1, z0), SIMD3(x1, y1, z1), n: SIMD3(1, 0, 0), uv: uv(d, h))
            p.quad(SIMD3(x0, y0, z0), SIMD3(x0, y0, z1), SIMD3(x0, y1, z1), SIMD3(x0, y1, z0), n: SIMD3(-1, 0, 0), uv: uv(d, h))
            p.quad(SIMD3(x0, y1, z1), SIMD3(x1, y1, z1), SIMD3(x1, y1, z0), SIMD3(x0, y1, z0), n: SIMD3(0, 1, 0), uv: uv(w, d))
            p.quad(SIMD3(x0, y0, z0), SIMD3(x1, y0, z0), SIMD3(x1, y0, z1), SIMD3(x0, y0, z1), n: SIMD3(0, -1, 0), uv: uv(w, d))
        }
    }

    /// Upright cylinder (or cone when the radii differ) standing on y0.
    func cylinder(_ cx: Float, _ y0: Float, _ cz: Float, r0: Float, r1: Float? = nil, h: Float, _ m: SCNMaterial, segs: Int = 14, cap: Bool = true) {
        let rt = r1 ?? r0
        edit(m) { p in
            let base = UInt32(p.positions.count)
            let slope = (r0 - rt) / max(0.0001, h)
            for s in 0...segs {
                let a = Float(s) / Float(segs) * 2 * Float.pi
                let c = cos(a), sn = sin(a)
                let n = simd_normalize(SIMD3<Float>(c, slope, sn))
                p.positions.append(SIMD3(cx + r0 * c, y0, cz + r0 * sn)); p.normals.append(n); p.uvs.append(SIMD2(Float(s) / Float(segs), 1))
                p.positions.append(SIMD3(cx + rt * c, y0 + h, cz + rt * sn)); p.normals.append(n); p.uvs.append(SIMD2(Float(s) / Float(segs), 0))
            }
            for s in 0..<segs {
                let a = base + UInt32(s * 2), b = a + 1, c = a + 2, d = a + 3
                p.indices += [a, d, c, a, b, d]
            }
            if cap && rt > 0.0005 {
                let center = UInt32(p.positions.count)
                p.positions.append(SIMD3(cx, y0 + h, cz)); p.normals.append(SIMD3(0, 1, 0)); p.uvs.append(SIMD2(0.5, 0.5))
                for s in 0...segs {
                    let a = Float(s) / Float(segs) * 2 * Float.pi
                    p.positions.append(SIMD3(cx + rt * cos(a), y0 + h, cz + rt * sin(a)))
                    p.normals.append(SIMD3(0, 1, 0)); p.uvs.append(SIMD2(0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a)))
                }
                for s in 0..<segs { p.indices += [center, center + UInt32(s) + 2, center + UInt32(s) + 1] }
            }
        }
    }

    var isEmpty: Bool { parts.isEmpty }

    func build() -> SCNNode? {
        let batch = MeshBatcher()
        for key in order {
            guard let part = parts[key], let m = mats[key], !part.indices.isEmpty else { continue }
            var b = MeshBatcher.Baked()
            b.positions = part.positions
            b.normals = part.normals
            b.uvs = part.uvs
            b.groups = [(m, part.indices)]
            batch.add(b)
        }
        return batch.build()
    }
}

/// Shared materials and generated textures for the store itself.
@MainActor
enum Mats {
    private static var cache: [String: SCNMaterial] = [:]

    static func shade(_ hex: UInt32, _ f: Double) -> UInt32 {
        func ch(_ v: UInt32) -> UInt32 { UInt32(max(0, min(255, (Double(v) * f).rounded()))) }
        return (ch((hex >> 16) & 0xFF) << 16) | (ch((hex >> 8) & 0xFF) << 8) | ch(hex & 0xFF)
    }

    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func ch(_ s: UInt32) -> UInt32 {
            let x = Double((a >> s) & 0xFF), y = Double((b >> s) & 0xFF)
            return UInt32(max(0, min(255, (x + (y - x) * t).rounded()))) << s
        }
        return ch(16) | ch(8) | ch(0)
    }

    /// Solid color. `gloss` 0 = matte.
    static func solid(_ hex: UInt32, gloss: CGFloat = 0, doubleSided: Bool = false) -> SCNMaterial {
        let key = "s\(hex)|\(gloss)|\(doubleSided)"
        if let m = cache[key] { return m }
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(hex: hex)
        if gloss > 0 {
            m.lightingModel = .blinn
            m.specular.contents = UIColor(white: gloss, alpha: 1)
            m.shininess = 0.4
        } else {
            m.lightingModel = .lambert
        }
        m.isDoubleSided = doubleSided
        cache[key] = m
        return m
    }

    static func glow(_ hex: UInt32) -> SCNMaterial {
        let key = "g\(hex)"
        if let m = cache[key] { return m }
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(hex: hex)
        m.lightingModel = .constant
        cache[key] = m
        return m
    }

    /// Tiling texture material (repeat wrap, mipmapped so it doesn't shimmer in the distance).
    static func tiled(_ key: String, gloss: CGFloat = 0, image: () -> UIImage) -> SCNMaterial {
        if let m = cache["t" + key] { return m }
        let m = SCNMaterial()
        m.diffuse.contents = image()
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 8
        if gloss > 0 {
            m.lightingModel = .blinn
            m.specular.contents = UIColor(white: gloss, alpha: 1)
            m.shininess = 0.6
        } else {
            m.lightingModel = .lambert
        }
        cache["t" + key] = m
        return m
    }

    /// A one-off picture (poster, sign) drawn unlit so it always reads clearly.
    static func picture(_ image: UIImage, lit: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = image
        m.diffuse.mipFilter = .linear
        m.lightingModel = lit ? .lambert : .constant
        m.isDoubleSided = true
        return m
    }

    // MARK: Textures

    /// Two-tone floor tiles with grout lines and a little speckle.
    static func floorTiles(_ a: UInt32, _ b: UInt32) -> UIImage {
        let size = CGSize(width: 256, height: 256)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        return UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            let c = ctx.cgContext
            for i in 0..<2 {
                for j in 0..<2 {
                    c.setFillColor(UIColor(hex: (i + j) % 2 == 0 ? a : b).cgColor)
                    c.fill(CGRect(x: i * 128, y: j * 128, width: 128, height: 128))
                }
            }
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func rnd() -> CGFloat {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return CGFloat(seed % 10_000) / 10_000
            }
            for _ in 0..<900 {
                c.setFillColor(UIColor(white: rnd() > 0.5 ? 1 : 0, alpha: 0.035 + rnd() * 0.04).cgColor)
                c.fill(CGRect(x: rnd() * 256, y: rnd() * 256, width: 1 + rnd() * 2, height: 1 + rnd() * 2))
            }
            c.setFillColor(UIColor(hex: shade(b, 0.8)).cgColor)
            for k in [0, 128] {
                c.fill(CGRect(x: 0, y: CGFloat(k) - 1, width: 256, height: 2.5))
                c.fill(CGRect(x: CGFloat(k) - 1, y: 0, width: 2.5, height: 256))
            }
        }
    }

    /// Suspended ceiling tiles with a metal grid.
    static func ceilingTiles() -> UIImage {
        let size = CGSize(width: 128, height: 128)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        return UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(hex: 0xECECE6).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            var seed: UInt64 = 88172645463325252
            func rnd() -> CGFloat {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return CGFloat(seed % 10_000) / 10_000
            }
            for _ in 0..<500 {
                c.setFillColor(UIColor(white: 0, alpha: 0.05 + rnd() * 0.06).cgColor)
                c.fillEllipse(in: CGRect(x: rnd() * 128, y: rnd() * 128, width: 1.5, height: 1.5))
            }
            c.setFillColor(UIColor(hex: 0xC9CBC6).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: 128, height: 3))
            c.fill(CGRect(x: 0, y: 0, width: 3, height: 128))
        }
    }

    /// Pegboard back panel for shelving.
    static func pegboard(_ base: UInt32) -> UIImage {
        let size = CGSize(width: 64, height: 64)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        return UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(hex: base).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            c.setFillColor(UIColor(hex: shade(base, 0.72)).cgColor)
            for i in 0..<4 { for j in 0..<4 { c.fillEllipse(in: CGRect(x: CGFloat(6 + i * 16), y: CGFloat(6 + j * 16), width: 3.2, height: 3.2)) } }
        }
    }

    /// Daylight through the shop windows: sky, a far row of buildings and a street.
    static func streetView() -> UIImage {
        let size = CGSize(width: 512, height: 256)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        return UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            let c = ctx.cgContext
            let colors = [UIColor(hex: 0x8EC5F0).cgColor, UIColor(hex: 0xDDF0FB).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 170), options: [.drawsAfterEndLocation])
            }
            var seed: UInt64 = 0xDEADBEEFCAFEF00D
            func rnd() -> CGFloat {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return CGFloat(seed % 10_000) / 10_000
            }
            var x: CGFloat = -10
            let tones: [UInt32] = [0xB8C4CE, 0xA9B6C2, 0xC6CED6, 0x9FAEBB, 0xD2C7B8]
            while x < 520 {
                let w = 40 + rnd() * 60, h = 50 + rnd() * 80
                c.setFillColor(UIColor(hex: tones[Int(rnd() * 4.99)]).cgColor)
                c.fill(CGRect(x: x, y: 175 - h, width: w, height: h))
                c.setFillColor(UIColor(white: 1, alpha: 0.35).cgColor)
                var wy = 175 - h + 8
                while wy < 165 {
                    var wx = x + 6
                    while wx < x + w - 8 { c.fill(CGRect(x: wx, y: wy, width: 5, height: 7)); wx += 12 }
                    wy += 14
                }
                x += w + 2
            }
            c.setFillColor(UIColor(hex: 0x7FA36B).cgColor)
            for _ in 0..<7 { let tx = rnd() * 512; c.fillEllipse(in: CGRect(x: tx, y: 150, width: 34, height: 30)) }
            c.setFillColor(UIColor(hex: 0x8B9097).cgColor)
            c.fill(CGRect(x: 0, y: 175, width: 512, height: 81))
            c.setFillColor(UIColor(hex: 0xC9CDD2).cgColor)
            c.fill(CGRect(x: 0, y: 175, width: 512, height: 14))
            c.setFillColor(UIColor(hex: 0xF4E3A1).cgColor)
            var lx: CGFloat = 10
            while lx < 512 { c.fill(CGRect(x: lx, y: 222, width: 34, height: 4)); lx += 70 }
        }
    }

    /// A promo poster.
    static func poster(_ title: String, _ sub: String, bg: UInt32, fg: UInt32) -> UIImage {
        let size = CGSize(width: 300, height: 400)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        return UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(hex: bg).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            c.setFillColor(UIColor(hex: shade(bg, 0.82)).cgColor)
            c.fillEllipse(in: CGRect(x: -80, y: 210, width: 460, height: 300))
            c.setStrokeColor(UIColor(hex: fg).cgColor)
            c.setLineWidth(8)
            c.stroke(CGRect(x: 14, y: 14, width: 272, height: 372))
            let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineHeightMultiple = 0.9
            (title as NSString).draw(in: CGRect(x: 24, y: 60, width: 252, height: 200), withAttributes: [
                .font: UIFont.systemFont(ofSize: 62, weight: .black), .foregroundColor: UIColor(hex: fg), .paragraphStyle: para])
            (sub as NSString).draw(in: CGRect(x: 24, y: 290, width: 252, height: 80), withAttributes: [
                .font: UIFont.systemFont(ofSize: 26, weight: .bold), .foregroundColor: UIColor(hex: fg).withAlphaComponent(0.9), .paragraphStyle: para])
        }
    }

    /// Text on a flat sign.
    static func label(_ text: String, size: CGSize, font: CGFloat, fg: UInt32, bg: UInt32, corner: CGFloat = 0) -> UIImage {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in
            UIColor(hex: bg).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: corner).fill()
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: font, weight: .black),
                                                        .foregroundColor: UIColor(hex: fg), .paragraphStyle: para]
            let h = (text as NSString).boundingRect(with: size, options: .usesLineFragmentOrigin, attributes: attrs, context: nil).height
            (text as NSString).draw(in: CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h), withAttributes: attrs)
        }
    }
}

/// Section styling: a stable color and an icon for every category.
enum SectionStyle {
    static let palette: [UInt32] = [0xC0392B, 0x2471A3, 0x1E8449, 0xB9770E, 0x7D3C98, 0x117A65, 0xBA4A00, 0x2E4053,
                                    0xA93226, 0x1F618D, 0x239B56, 0xAF601A, 0x6C3483, 0x148F77, 0x873600, 0x5D6D7E]

    private static let icons: [String: String] = [
        "Pantry": "🥫", "Snacks": "🍪", "Drinks": "🥤", "Dairy": "🥛", "Frozen": "❄️", "Bakery": "🍞",
        "Condiments": "🍅", "Baking": "🧁", "Meat": "🥩", "Paint": "🎨", "Fasteners": "🔩", "Supplies": "🧰",
        "Electrical": "💡", "Tools": "🔨", "Power Tools": "🛠️", "Security": "🔒", "Health": "💊", "First Aid": "🩹",
        "Personal Care": "🧴", "Oral Care": "🦷", "Cold Care": "🧊", "Power": "🔌", "Audio": "🎧", "Gaming": "🎮",
        "Accessories": "📱", "Computer": "💻", "Cables": "🔗", "Wearables": "⌚️", "Dog": "🐶", "Cat": "🐱",
        "Toys": "🧸", "Fish": "🐟", "Birds": "🐦", "Grooming": "🧼", "Bowls & Beds": "🥣", "Small Pets": "🐹",
        "Seeds": "🌱", "Soil": "🪴", "Pots": "🏺", "Watering": "💧", "Pest Control": "🐛",
    ]

    static func color(_ category: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for u in category.unicodeScalars { h = (h ^ u.value) &* 16777619 }
        return palette[Int(h % UInt32(palette.count))]
    }

    static func icon(_ category: String) -> String { icons[category] ?? "🏷️" }
}
