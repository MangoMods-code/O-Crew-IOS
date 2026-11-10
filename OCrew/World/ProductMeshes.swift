import SceneKit
import UIKit
import simd

/// A piece of mesh that uses one material.
struct MeshPart {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []
    let material: Int

    init(material: Int) { self.material = material }

    /// a, b, c, d go around the quad; normal is given explicitly.
    mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, n: SIMD3<Float>,
                       uv: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>) = (SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0))) {
        let base = UInt32(positions.count)
        positions += [a, b, c, d]
        normals += [n, n, n, n]
        uvs += [uv.0, uv.1, uv.2, uv.3]
        indices += [base, base + 1, base + 2, base, base + 2, base + 3]
    }

    mutating func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, n: SIMD3<Float>) {
        let base = UInt32(positions.count)
        positions += [a, b, c]
        normals += [n, n, n]
        uvs += [SIMD2(0, 1), SIMD2(1, 1), SIMD2(0.5, 0)]
        indices += [base, base + 1, base + 2]
    }
}

/// A product model built from our own vertices, with its materials.
@MainActor
final class ProductMesh {
    // Material slots
    static let label = 0, side = 1, base = 2, accent = 3, metal = 4, sticker = 5

    let parts: [MeshPart]
    let materials: [SCNMaterial]
    private var cachedGeometry: SCNGeometry?

    init(parts: [MeshPart], materials: [SCNMaterial]) {
        self.parts = parts.filter { !$0.indices.isEmpty }
        self.materials = materials
    }

    func node() -> SCNNode {
        if cachedGeometry == nil {
            let b = MeshBatcher()
            b.add(self, transform: matrix_identity_float4x4)
            cachedGeometry = b.buildGeometry()
        }
        return SCNNode(geometry: cachedGeometry)
    }

    // MARK: Building

    private static var cache: [String: ProductMesh] = [:]

    static func of(_ p: Product, expired: Bool) -> ProductMesh {
        let key = (expired ? "x:" : "") + p.id
        if let m = cache[key] { return m }
        let mats = materialsFor(p, expired: expired)
        var parts: [MeshPart]
        let front: (z: Float, y: Float)
        switch p.shape {
        case let .box(w, h, d):
            if isFlat(p) {
                parts = flatBox(w, h, d)
                front = (d / 2, h * 0.5)
            } else {
                parts = box(w, h, d, top: base)
                front = (d / 2, h * 0.5)
            }
        case let .bag(w, h, d):
            parts = bag(w, h, d)
            front = (d / 2, h * 0.5)
        case let .carton(w, h, d):
            parts = carton(w, h, d)
            front = (d / 2, h * 0.5)
        case let .can(r, h):
            parts = lathe(r: r, profile: [(0, 0), (0.9, 0), (1, 0.012), (1, h - 0.012), (0.94, h), (0.8, h - 0.005), (0, h - 0.005)],
                          mats: [metal, metal, label, metal, metal, metal], labelBand: 2)
            front = (r, h * 0.5)
        case let .jar(r, h):
            parts = lathe(r: r, profile: [(0, 0), (0.94, 0), (1, 0.012), (1, h * 0.76), (0.9, h * 0.8), (0.98, h * 0.81),
                                          (0.98, h - 0.006), (0.9, h), (0, h)],
                          mats: [base, base, label, base, accent, accent, accent, accent], labelBand: 2)
            front = (r, h * 0.4)
        case let .bottle(r, h):
            parts = lathe(r: r, profile: [(0, 0), (0.92, 0), (1, 0.015), (1, h * 0.6), (0.96, h * 0.68), (0.72, h * 0.77),
                                          (0.44, h * 0.83), (0.42, h * 0.87), (0.48, h * 0.88), (0.48, h - 0.004), (0.38, h), (0, h)],
                          mats: [base, base, label, base, base, base, base, accent, accent, accent, accent], labelBand: 2)
            front = (r, h * 0.32)
        }
        if expired {
            var s = MeshPart(material: sticker)
            let sw: Float = 0.045, sh: Float = 0.03, z = front.z + 0.003, y = front.y
            s.quad(SIMD3(-sw / 2, y - sh / 2, z), SIMD3(sw / 2, y - sh / 2, z), SIMD3(sw / 2, y + sh / 2, z), SIMD3(-sw / 2, y + sh / 2, z),
                   n: SIMD3(0, 0, 1))
            parts.append(s)
        }
        let m = ProductMesh(parts: parts, materials: mats)
        cache[key] = m
        return m
    }

    /// Rectangular box, origin at bottom-center, label on front and back.
    static func box(_ w: Float, _ h: Float, _ d: Float, top: Int) -> [MeshPart] {
        let x = w / 2, z = d / 2
        var lab = MeshPart(material: label), sd = MeshPart(material: side), tp = MeshPart(material: top)
        lab.quad(SIMD3(-x, 0, z), SIMD3(x, 0, z), SIMD3(x, h, z), SIMD3(-x, h, z), n: SIMD3(0, 0, 1))
        lab.quad(SIMD3(x, 0, -z), SIMD3(-x, 0, -z), SIMD3(-x, h, -z), SIMD3(x, h, -z), n: SIMD3(0, 0, -1))
        sd.quad(SIMD3(x, 0, z), SIMD3(x, 0, -z), SIMD3(x, h, -z), SIMD3(x, h, z), n: SIMD3(1, 0, 0))
        sd.quad(SIMD3(-x, 0, -z), SIMD3(-x, 0, z), SIMD3(-x, h, z), SIMD3(-x, h, -z), n: SIMD3(-1, 0, 0))
        tp.quad(SIMD3(-x, h, z), SIMD3(x, h, z), SIMD3(x, h, -z), SIMD3(-x, h, -z), n: SIMD3(0, 1, 0))
        tp.quad(SIMD3(-x, 0, -z), SIMD3(x, 0, -z), SIMD3(x, 0, z), SIMD3(-x, 0, z), n: SIMD3(0, -1, 0))
        return [lab, sd, tp]
    }

    /// Flat packs (pizza, bacon, butter…) lie down, so their art goes on the big top face.
    static func isFlat(_ p: Product) -> Bool {
        if case let .box(w, h, d) = p.shape { return h < 0.6 * min(w, d) }
        return false
    }

    static func flatBox(_ w: Float, _ h: Float, _ d: Float) -> [MeshPart] {
        let x = w / 2, z = d / 2
        var lab = MeshPart(material: label), sd = MeshPart(material: side)
        lab.quad(SIMD3(-x, h, z), SIMD3(x, h, z), SIMD3(x, h, -z), SIMD3(-x, h, -z), n: SIMD3(0, 1, 0))
        lab.quad(SIMD3(-x, 0, -z), SIMD3(x, 0, -z), SIMD3(x, 0, z), SIMD3(-x, 0, z), n: SIMD3(0, -1, 0))
        sd.quad(SIMD3(-x, 0, z), SIMD3(x, 0, z), SIMD3(x, h, z), SIMD3(-x, h, z), n: SIMD3(0, 0, 1))
        sd.quad(SIMD3(x, 0, -z), SIMD3(-x, 0, -z), SIMD3(-x, h, -z), SIMD3(x, h, -z), n: SIMD3(0, 0, -1))
        sd.quad(SIMD3(x, 0, z), SIMD3(x, 0, -z), SIMD3(x, h, -z), SIMD3(x, h, z), n: SIMD3(1, 0, 0))
        sd.quad(SIMD3(-x, 0, -z), SIMD3(-x, 0, z), SIMD3(-x, h, z), SIMD3(-x, h, -z), n: SIMD3(-1, 0, 0))
        return [lab, sd]
    }

    /// Pillow-shaped snack bag with crimped seals top and bottom.
    static func bag(_ w: Float, _ h: Float, _ d: Float) -> [MeshPart] {
        var lab = MeshPart(material: label), seal = MeshPart(material: accent)
        let n = 8
        let y0 = h * 0.07, y1 = h * 0.93
        func bulge(_ u: Float, _ v: Float) -> Float {
            let a = 2 * u - 1, b = 2 * v - 1
            return (1 - a * a * a * a) * (1 - b * b * b * b)
        }
        func point(_ u: Float, _ v: Float, _ side: Float) -> SIMD3<Float> {
            SIMD3((u - 0.5) * w * (1 - 0.06 * bulge(u, v)), y0 + v * (y1 - y0), side * d / 2 * bulge(u, v))
        }
        for side in [Float(1), Float(-1)] {
            let base = UInt32(lab.positions.count)
            for j in 0...n {
                for i in 0...n {
                    let u = Float(i) / Float(n), v = Float(j) / Float(n)
                    let p = point(u, v, side)
                    let e: Float = 0.01
                    let du = point(min(1, u + e), v, side) - point(max(0, u - e), v, side)
                    let dv = point(u, min(1, v + e), side) - point(u, max(0, v - e), side)
                    var nn = simd_normalize(simd_cross(du, dv))
                    if nn.z * side < 0 { nn = -nn }
                    lab.positions.append(p)
                    lab.normals.append(nn)
                    lab.uvs.append(SIMD2(side > 0 ? u : 1 - u, 1 - v))
                }
            }
            for j in 0..<n {
                for i in 0..<n {
                    let a = base + UInt32(j * (n + 1) + i)
                    let b = a + 1, c = a + UInt32(n + 1) + 1, dd = a + UInt32(n + 1)
                    lab.indices += [a, b, c, a, c, dd]
                }
            }
        }
        // Crimped seals (thin flaps)
        for (ya, yb) in [(Float(0), y0), (y1, h)] {
            seal.quad(SIMD3(-w / 2, ya, 0.004), SIMD3(w / 2, ya, 0.004), SIMD3(w / 2, yb, 0.004), SIMD3(-w / 2, yb, 0.004), n: SIMD3(0, 0, 1))
            seal.quad(SIMD3(w / 2, ya, -0.004), SIMD3(-w / 2, ya, -0.004), SIMD3(-w / 2, yb, -0.004), SIMD3(w / 2, yb, -0.004), n: SIMD3(0, 0, -1))
        }
        return [lab, seal]
    }

    /// Milk/juice carton: box with a gable top and a sealed fin.
    static func carton(_ w: Float, _ h: Float, _ d: Float) -> [MeshPart] {
        var parts = box(w, h, d, top: base)
        var roof = MeshPart(material: base), gable = MeshPart(material: side)
        let x = w / 2, z = d / 2, r: Float = 0.035
        let fn = simd_normalize(SIMD3<Float>(0, z, r)), bn = simd_normalize(SIMD3<Float>(0, z, -r))
        roof.quad(SIMD3(-x, h, z), SIMD3(x, h, z), SIMD3(x, h + r, 0), SIMD3(-x, h + r, 0), n: fn)
        roof.quad(SIMD3(x, h, -z), SIMD3(-x, h, -z), SIMD3(-x, h + r, 0), SIMD3(x, h + r, 0), n: bn)
        gable.triangle(SIMD3(x, h, z), SIMD3(x, h, -z), SIMD3(x, h + r, 0), n: SIMD3(1, 0, 0))
        gable.triangle(SIMD3(-x, h, -z), SIMD3(-x, h, z), SIMD3(-x, h + r, 0), n: SIMD3(-1, 0, 0))
        roof.quad(SIMD3(-x, h + r, 0.002), SIMD3(x, h + r, 0.002), SIMD3(x, h + r + 0.014, 0.002), SIMD3(-x, h + r + 0.014, 0.002), n: SIMD3(0, 0, 1))
        roof.quad(SIMD3(x, h + r, -0.002), SIMD3(-x, h + r, -0.002), SIMD3(-x, h + r + 0.014, -0.002), SIMD3(x, h + r + 0.014, -0.002), n: SIMD3(0, 0, -1))
        parts.append(roof)
        parts.append(gable)
        return parts
    }

    /// Surface of revolution. `profile` is (radius fraction, height) from bottom center to top center.
    static func lathe(r: Float, profile: [(Float, Float)], mats: [Int], labelBand: Int) -> [MeshPart] {
        let segs = 16
        var byMat: [Int: MeshPart] = [:]
        let labY0 = profile[labelBand].1, labY1 = profile[labelBand + 1].1
        for k in 0..<(profile.count - 1) {
            let m = mats[k]
            var part = byMat[m] ?? MeshPart(material: m)
            let (ra, ya) = (profile[k].0 * r, profile[k].1)
            let (rb, yb) = (profile[k + 1].0 * r, profile[k + 1].1)
            let dr = rb - ra, dy = yb - ya
            let len = max(1e-5, sqrt(dr * dr + dy * dy))
            let n2 = SIMD2<Float>(dy / len, -dr / len)    // outward in the (radius, y) plane
            let base = UInt32(part.positions.count)
            for s in 0...segs {
                let t = Float(s) / Float(segs) * 2 * .pi
                let c = cos(t), sn = sin(t)
                let nrm = SIMD3<Float>(n2.x * c, n2.y, n2.x * sn)
                let isLabel = m == label
                let va: Float = isLabel ? 1 - (ya - labY0) / max(1e-5, labY1 - labY0) : 0.5
                let vb: Float = isLabel ? 1 - (yb - labY0) / max(1e-5, labY1 - labY0) : 0.5
                let u = Float(s) / Float(segs)
                part.positions.append(SIMD3(ra * c, ya, ra * sn))
                part.normals.append(nrm)
                part.uvs.append(SIMD2(u, va))
                part.positions.append(SIMD3(rb * c, yb, rb * sn))
                part.normals.append(nrm)
                part.uvs.append(SIMD2(u, vb))
            }
            for s in 0..<segs {
                let a = base + UInt32(s * 2), b = a + 1, c = a + 2, d = a + 3
                part.indices += [a, c, d, a, d, b]
            }
            byMat[m] = part
        }
        return Array(byMat.values).sorted { $0.material < $1.material }
    }

    // MARK: Materials & packaging art

    private static func materialsFor(_ p: Product, expired: Bool) -> [SCNMaterial] {
        let tint = UIColor(hex: 0x9C8B6E)
        func m(_ contents: Any, shine: CGFloat) -> SCNMaterial {
            let mat = SCNMaterial()
            mat.diffuse.contents = contents
            mat.diffuse.mipFilter = .linear
            mat.diffuse.maxAnisotropy = 4
            mat.lightingModel = .blinn
            mat.specular.contents = UIColor(white: shine, alpha: 1)
            mat.shininess = 0.35
            mat.isDoubleSided = true
            if expired { mat.multiply.contents = tint }
            return mat
        }
        let metal = m(UIColor(hex: 0xC9CED3), shine: 0.6)
        let sticker = SCNMaterial()
        sticker.diffuse.contents = UIColor(hex: 0xE02424)
        sticker.emission.contents = UIColor(hex: 0x7A0000)
        sticker.lightingModel = .constant
        sticker.isDoubleSided = true
        return [
            m(Packaging.front(p), shine: 0.18),
            m(Packaging.side(p), shine: 0.12),
            m(UIColor(hex: p.color), shine: 0.15),
            m(UIColor(hex: p.accent), shine: 0.25),
            metal,
            sticker,
        ]
    }
}

/// Soft contact shadow under floor items (one shared material, merged per floor chunk).
@MainActor
enum ContactShadow {
    static let mesh: ProductMesh = {
        var q = MeshPart(material: 0)
        q.quad(SIMD3(-0.5, 0, 0.5), SIMD3(0.5, 0, 0.5), SIMD3(0.5, 0, -0.5), SIMD3(-0.5, 0, -0.5), n: SIMD3(0, 1, 0))
        let size = CGSize(width: 64, height: 64)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(white: 0, alpha: 0.55).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                                                 endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
            }
        }
        let m = SCNMaterial()
        m.diffuse.contents = img
        m.lightingModel = .constant
        m.writesToDepthBuffer = false
        m.blendMode = .alpha
        m.transparencyMode = .aOne
        return ProductMesh(parts: [q], materials: [m])
    }()
}

/// Generated packaging artwork (fictional brands only).
@MainActor
enum Packaging {
    private static var fronts: [String: UIImage] = [:]
    private static var sides: [String: UIImage] = [:]
    private static let brands = ["Harvest Co.", "Northside", "Kitchen Gold", "Fresh Lane", "Brightway", "Pantry Pal",
                                 "Urban Basics", "Sunny Acre", "BlueOak", "Maple & Co.", "Everyday", "Crestline"]

    private static func hash(_ s: String) -> Int {
        var h = 5381
        for c in s.unicodeScalars { h = (h &* 33) &+ Int(c.value) }
        return abs(h)
    }

    static func brand(_ p: Product) -> String { brands[hash(p.id) % brands.count] }

    private static func shade(_ hex: UInt32, _ f: Double) -> UInt32 {
        func ch(_ v: UInt32) -> UInt32 { UInt32(max(0, min(255, (Double(v) * f).rounded()))) }
        return (ch((hex >> 16) & 0xFF) << 16) | (ch((hex >> 8) & 0xFF) << 8) | ch(hex & 0xFF)
    }

    private static func isDark(_ hex: UInt32) -> Bool {
        let r = Double((hex >> 16) & 0xFF), g = Double((hex >> 8) & 0xFF), b = Double(hex & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) < 150
    }

    private static func weightText(_ p: Product) -> String {
        let s = p.shape.size
        let grams = Int((s.w * s.h * s.d * 1_000_000 * 0.45).rounded())
        if p.category == "Drinks" || p.category == "Dairy" { return "\(max(250, grams / 10 * 10)) mL" }
        return "NET WT \(max(50, grams / 10 * 10)) g"
    }

    /// Front label. Cylinders get a wide wrap with the art twice (front and back).
    static func front(_ p: Product) -> UIImage {
        if let i = fronts[p.id] { return i }
        let round: Bool
        switch p.shape {
        case .can, .jar, .bottle: round = true
        default: round = false
        }
        let s = p.shape.size
        let faceH = ProductMesh.isFlat(p) ? s.d : s.h      // flat packs show their top
        let size = round ? CGSize(width: 512, height: 256)
                         : CGSize(width: 256, height: CGFloat(max(96, min(512, 256 * faceH / max(0.01, s.w)))))
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            let panelW = round ? size.width / 2 : size.width
            let panels = round ? 2 : 1
            for k in 0..<panels {
                c.saveGState()
                c.translateBy(x: CGFloat(k) * panelW, y: 0)
                drawPanel(c, CGSize(width: panelW, height: size.height), p)
                c.restoreGState()
            }
        }
        fronts[p.id] = img
        return img
    }

    private static func drawPanel(_ c: CGContext, _ size: CGSize, _ p: Product) {
        let W = size.width, H = size.height
        let base = UIColor(hex: p.color), accent = UIColor(hex: p.accent)
        let dark = isDark(p.color)
        // Background gradient
        let lighter = UIColor(hex: shade(p.color, 1.12)), darker = UIColor(hex: shade(p.color, 0.8))
        let colors = [lighter.cgColor, base.cgColor, darker.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: H), options: [])
        }
        c.setFillColor(UIColor(white: dark ? 1 : 0, alpha: 0.08).cgColor)
        c.fill(CGRect(x: 0, y: H * 0.72, width: W, height: H * 0.28))
        // Accent swoosh
        c.setFillColor(accent.cgColor)
        c.move(to: CGPoint(x: 0, y: H * 0.58))
        c.addCurve(to: CGPoint(x: W, y: H * 0.5), control1: CGPoint(x: W * 0.35, y: H * 0.42), control2: CGPoint(x: W * 0.65, y: H * 0.66))
        c.addLine(to: CGPoint(x: W, y: H * 0.64))
        c.addCurve(to: CGPoint(x: 0, y: H * 0.7), control1: CGPoint(x: W * 0.65, y: H * 0.78), control2: CGPoint(x: W * 0.35, y: H * 0.56))
        c.closePath()
        c.fillPath()
        // "Product shot" circle
        let r = min(W, H) * 0.16
        c.setFillColor(UIColor.white.withAlphaComponent(0.92).cgColor)
        c.fillEllipse(in: CGRect(x: W * 0.68 - r, y: H * 0.6 - r, width: r * 2, height: r * 2))
        c.setFillColor(accent.cgColor)
        c.fillEllipse(in: CGRect(x: W * 0.68 - r * 0.62, y: H * 0.6 - r * 0.62, width: r * 1.24, height: r * 1.24))
        c.setFillColor(base.cgColor)
        c.fillEllipse(in: CGRect(x: W * 0.68 - r * 0.28, y: H * 0.6 - r * 0.28, width: r * 0.56, height: r * 0.56))

        let ink = dark ? UIColor.white : UIColor(hex: 0x1B1B1B)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        // Brand pill
        let brand = brand(p).uppercased() as NSString
        let bf = UIFont.systemFont(ofSize: max(10, W * 0.075), weight: .heavy)
        let bs = brand.size(withAttributes: [.font: bf])
        let pill = CGRect(x: (W - bs.width) / 2 - 8, y: H * 0.05, width: bs.width + 16, height: bs.height + 4)
        c.setFillColor(accent.cgColor)
        c.addPath(UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2).cgPath)
        c.fillPath()
        brand.draw(at: CGPoint(x: pill.minX + 8, y: pill.minY + 2), withAttributes: [
            .font: bf, .foregroundColor: isDark(p.accent) ? UIColor.white : UIColor(hex: 0x1B1B1B)])
        // Product name
        var fontSize = W * 0.17
        let name = p.name as NSString
        let box = CGRect(x: W * 0.06, y: H * 0.17, width: W * 0.88, height: H * 0.32)
        var attrs: [NSAttributedString.Key: Any] = [:]
        while fontSize > 9 {
            attrs = [.font: UIFont.systemFont(ofSize: fontSize, weight: .black), .foregroundColor: ink, .paragraphStyle: para]
            let need = name.boundingRect(with: CGSize(width: box.width, height: .greatestFiniteMagnitude),
                                         options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
            if need.height <= box.height { break }
            fontSize -= 1
        }
        name.draw(with: box, options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
        // Weight line
        let wt = weightText(p) as NSString
        let wf = UIFont.systemFont(ofSize: max(8, W * 0.055), weight: .semibold)
        wt.draw(in: CGRect(x: W * 0.06, y: H * 0.86, width: W * 0.88, height: H * 0.12),
                withAttributes: [.font: wf, .foregroundColor: ink.withAlphaComponent(0.85), .paragraphStyle: para])
    }

    /// Side panel: nutrition box + barcode.
    static func side(_ p: Product) -> UIImage {
        if let i = sides[p.id] { return i }
        let size = CGSize(width: 128, height: 256)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(hex: p.color).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            c.setFillColor(UIColor(hex: p.accent).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: 128, height: 18))
            c.setFillColor(UIColor.white.cgColor)
            c.fill(CGRect(x: 12, y: 32, width: 104, height: 120))
            c.setFillColor(UIColor(hex: 0x222222).cgColor)
            c.fill(CGRect(x: 18, y: 38, width: 70, height: 8))
            for i in 0..<9 {
                c.fill(CGRect(x: 18, y: 54 + CGFloat(i) * 10, width: CGFloat(40 + (hash(p.id + "\(i)") % 50)), height: 3))
                c.fill(CGRect(x: 96, y: 54 + CGFloat(i) * 10, width: 14, height: 3))
            }
            c.setFillColor(UIColor.white.cgColor)
            c.fill(CGRect(x: 18, y: 172, width: 92, height: 56))
            c.setFillColor(UIColor.black.cgColor)
            var x: CGFloat = 24
            var k = hash(p.id)
            while x < 104 {
                let w = CGFloat(1 + k % 3)
                c.fill(CGRect(x: x, y: 178, width: w, height: 38))
                x += w + CGFloat(1 + (k / 3) % 3)
                k = k / 7 + 31 * (k % 7) + 3
            }
        }
        sides[p.id] = img
        return img
    }
}
