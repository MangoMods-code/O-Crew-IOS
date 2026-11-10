import SwiftUI
import SceneKit
import simd

/// A live, fully stocked aisle drifting past behind the main menu.
@MainActor
struct StoreBackdrop: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        let scene = MenuScene.make()
        v.scene = scene
        v.pointOfView = scene.rootNode.childNode(withName: "menuCamera", recursively: false)
        v.backgroundColor = UIColor(hex: 0x0E1014)
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 30
        v.isUserInteractionEnabled = false
        v.isPlaying = true
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {}
}

@MainActor
enum MenuScene {
    private static let units: [(FixtureKind, [(String, String, String)])] = [
        (.freezer, [("Frozen", "pizza", "icecream"), ("Frozen", "fries", "waffles"), ("Frozen", "nuggets", "frozenveg")]),
        (.fridge, [("Dairy", "milk", "eggs"), ("Dairy", "yogurt", "butter"), ("Drinks", "water", "soda")]),
        (.shelf, [("Pantry", "cereal", "pasta"), ("Pantry", "soup", "beans"), ("Pantry", "rice", "oatmeal")]),
        (.shelf, [("Snacks", "chips", "cookies"), ("Snacks", "crackers", "candy"), ("Snacks", "granola", "chips")]),
        (.shelf, [("Condiments", "ketchup", "mustard"), ("Condiments", "mayo", "hotsauce"), ("Baking", "flour", "sugar")]),
        (.shelf, [("Bakery", "bread", "bagels"), ("Pantry", "coffee", "tea"), ("Pantry", "peanutbutter", "oil")]),
    ]

    static func make() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(hex: 0x0E1014)
        let theme = Levels.themes[0]
        let W: Float = Float(units.count) * 2 + 6, D: Float = 9, H: Float = 3.3
        let env = MeshBuilder()
        let floorMat = Mats.tiled("floor\(theme.floor)-\(theme.floorAlt)", gloss: 0.22) { Mats.floorTiles(theme.floor, theme.floorAlt) }
        let ft: Float = 1 / 1.2
        env.quad(SIMD3(-3, 0, D), SIMD3(W, 0, D), SIMD3(W, 0, 0), SIMD3(-3, 0, 0), floorMat,
                 uv: (SIMD2(0, D * ft), SIMD2((W + 3) * ft, D * ft), SIMD2((W + 3) * ft, 0), SIMD2(0, 0)))
        func strip(_ y0: Float, _ y1: Float, _ m: SCNMaterial) {
            env.quad(SIMD3(-3, y0, 0), SIMD3(W, y0, 0), SIMD3(W, y1, 0), SIMD3(-3, y1, 0), m)
        }
        strip(0, 0.14, Mats.solid(Mats.shade(theme.trim, 0.6)))
        strip(0.14, 2.56, Mats.solid(theme.wall))
        strip(2.56, 2.8, Mats.solid(theme.trim, gloss: 0.15))
        strip(2.8, H, Mats.solid(theme.wall))
        let ct: Float = 1 / 0.6
        env.quad(SIMD3(-3, H, 0), SIMD3(W, H, 0), SIMD3(W, H, D), SIMD3(-3, H, D), Mats.tiled("ceiling") { Mats.ceilingTiles() },
                 uv: (SIMD2(0, 0), SIMD2((W + 3) * ct, 0), SIMD2((W + 3) * ct, D * ct), SIMD2(0, D * ct)))
        var lx: Float = 0
        while lx < W {
            env.quad(SIMD3(lx - 0.6, H - 0.012, 1.7), SIMD3(lx + 0.6, H - 0.012, 1.7),
                     SIMD3(lx + 0.6, H - 0.012, 2.3), SIMD3(lx - 0.6, H - 0.012, 2.3), Mats.glow(0xFFFDF4))
            lx += 2.4
        }
        if let shell = env.build() {
            shell.castsShadow = false
            scene.rootNode.addChildNode(shell)
        }

        var id = 1
        for (i, unit) in units.enumerated() {
            let kind = unit.0
            let depth: Float = kind == .shelf ? 0.5 : 0.7
            let spec = FixtureSpec(kind: kind, center: SIMD2(1.5 + Float(i) * 2.0 + 1.0, depth / 2 + 0.05), normal: SIMD2(0, 1), length: 2)
            let f = Fixture(index: i, spec: spec, shelfColor: theme.shelfColor, trim: theme.trim)
            for (row, r) in unit.1.enumerated() {
                for (k, pid) in [r.1, r.2].enumerated() {
                    guard let p = Catalog.product(pid) else { continue }
                    let slot = f.slots[row * 2 + k]
                    for _ in 0..<Slot.capacity(for: p) {
                        slot.items.append(Item(id: id, product: pid, expired: false))
                        id += 1
                    }
                    slot.rebuild()
                }
            }
            f.setRows(unit.1.map { $0.0 }, showLabels: true, signScale: 1)
            scene.rootNode.addChildNode(f.node)
        }

        let ambient = SCNNode(); ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 500
        ambient.light!.color = UIColor(hex: 0xFFF8EE)
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode(); key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 650
        key.light!.castsShadow = true
        key.light!.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.light!.shadowSampleCount = 8
        key.light!.shadowRadius = 4
        key.light!.shadowColor = UIColor(white: 0, alpha: 0.36)
        key.eulerAngles = SCNVector3(Float(-1.1), Float(0.4), Float(0))
        scene.rootNode.addChildNode(key)
        let fill = SCNNode(); fill.light = SCNLight()
        fill.light!.type = .directional
        fill.light!.intensity = 240
        fill.eulerAngles = SCNVector3(Float(-0.5), Float.pi + 0.5, Float(0))
        scene.rootNode.addChildNode(fill)

        // Camera drifts slowly along the aisle and back.
        let cam = SCNNode()
        cam.name = "menuCamera"
        cam.camera = SCNCamera()
        cam.camera!.fieldOfView = 46
        cam.camera!.zNear = 0.1
        cam.camera!.zFar = 60
        let x0: Float = 4.2, x1: Float = Float(units.count) * 2 + 0.8
        cam.position = SCNVector3(x0, 1.38, 3.3)
        cam.eulerAngles = SCNVector3(Float(-0.05), Float(-0.22), Float(0))
        let go = SCNAction.group([.move(to: SCNVector3(x1, 1.38, 3.3), duration: 26), .rotateTo(x: -0.05, y: 0.22, z: 0, duration: 26)])
        let back = SCNAction.group([.move(to: SCNVector3(x0, 1.38, 3.3), duration: 26), .rotateTo(x: -0.05, y: -0.22, z: 0, duration: 26)])
        go.timingMode = .easeInEaseOut
        back.timingMode = .easeInEaseOut
        cam.runAction(.repeatForever(.sequence([go, back])))
        scene.rootNode.addChildNode(cam)
        return scene
    }
}
