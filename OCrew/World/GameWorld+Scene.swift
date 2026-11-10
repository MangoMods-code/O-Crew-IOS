import SceneKit
import simd
import UIKit

/// Builds the store itself: room, windows, lighting, shelving and the scenery by the entrance.
extension GameWorld {
    func buildScene() {
        let W = layout.width, D = layout.depth, H = layout.height
        let theme = level.theme
        scene.background.contents = UIColor(hex: 0x9CC9EA)
        let env = MeshBuilder()      // room shell: receives shadows, never casts them
        let props = MeshBuilder()    // scenery that casts shadows

        // ---- Floor
        let floorMat = Mats.tiled("floor\(theme.floor)-\(theme.floorAlt)", gloss: 0.22) { Mats.floorTiles(theme.floor, theme.floorAlt) }
        let ft: Float = 1 / 1.2
        env.quad(SIMD3(0, 0, D), SIMD3(W, 0, D), SIMD3(W, 0, 0), SIMD3(0, 0, 0), floorMat,
                 uv: (SIMD2(0, D * ft), SIMD2(W * ft, D * ft), SIMD2(W * ft, 0), SIMD2(0, 0)))

        // ---- Walls (p0 is always on the viewer's left when facing the wall from inside)
        let wallMat = Mats.solid(theme.wall)
        let dadoMat = Mats.solid(Mats.shade(theme.wall, 0.9))
        let trimMat = Mats.solid(theme.trim, gloss: 0.15)
        let baseMat = Mats.solid(Mats.shade(theme.trim, 0.6))
        func strip(_ p0: SIMD2<Float>, _ p1: SIMD2<Float>, _ y0: Float, _ y1: Float, _ m: SCNMaterial) {
            env.quad(SIMD3(p0.x, y0, p0.y), SIMD3(p1.x, y0, p1.y), SIMD3(p1.x, y1, p1.y), SIMD3(p0.x, y1, p0.y), m)
        }
        func wall(_ p0: SIMD2<Float>, _ p1: SIMD2<Float>) {
            strip(p0, p1, 0, 0.14, baseMat)
            strip(p0, p1, 0.14, 0.98, dadoMat)
            strip(p0, p1, 0.98, 1.03, trimMat)
            strip(p0, p1, 1.03, 2.56, wallMat)
            strip(p0, p1, 2.56, 2.8, trimMat)
            strip(p0, p1, 2.8, H, wallMat)
        }
        wall(SIMD2(0, 0), SIMD2(W, 0))
        wall(SIMD2(W, 0), SIMD2(W, D))
        wall(SIMD2(W, D), SIMD2(layout.doorMaxX, D))
        wall(SIMD2(layout.doorMinX, D), SIMD2(0, D))
        wall(SIMD2(0, D), SIMD2(0, 0))
        strip(SIMD2(layout.doorMaxX, D), SIMD2(layout.doorMinX, D), 2.4, 2.56, wallMat)
        strip(SIMD2(layout.doorMaxX, D), SIMD2(layout.doorMinX, D), 2.56, 2.8, trimMat)
        strip(SIMD2(layout.doorMaxX, D), SIMD2(layout.doorMinX, D), 2.8, H, wallMat)

        // ---- Entrance: closed double doors, mat, signs
        let doorW = layout.doorMaxX - layout.doorMinX
        let dcx = (layout.doorMinX + layout.doorMaxX) / 2
        let steel = Mats.solid(0x4B5661, gloss: 0.35)
        let frosted = Mats.glow(0xD9E8F0)
        for side in [Float(-1), Float(1)] {
            let cx = dcx + side * doorW / 4
            env.box(cx, 1.2, D + 0.04, doorW / 2 - 0.02, 2.4, 0.06, steel)
            env.box(cx, 1.3, D + 0.035, doorW / 2 - 0.22, 1.9, 0.075, frosted)
            env.box(cx, 1.05, D - 0.01, doorW / 2 - 0.3, 0.05, 0.06, Mats.solid(0xB8BFC6, gloss: 0.6))
        }
        env.box(layout.doorMinX - 0.03, 1.2, D, 0.06, 2.4, 0.1, steel)
        env.box(layout.doorMaxX + 0.03, 1.2, D, 0.06, 2.4, 0.1, steel)
        env.box(dcx, 2.43, D, doorW + 0.12, 0.06, 0.1, steel)
        let matRug = Mats.solid(0x2A2E35)
        env.quad(SIMD3(dcx - 1.15, 0.004, D - 0.06), SIMD3(dcx + 1.15, 0.004, D - 0.06),
                 SIMD3(dcx + 1.15, 0.004, D - 1.0), SIMD3(dcx - 1.15, 0.004, D - 1.0), matRug)
        let closedSign = Mats.picture(Mats.label("SORRY, WE'RE CLOSED", size: CGSize(width: 600, height: 130), font: 50,
                                                 fg: 0xFFFFFF, bg: 0xB03A2E, corner: 26))
        strip(SIMD2(dcx + 0.55, D - 0.006), SIMD2(dcx - 0.55, D - 0.006), 1.48, 1.72, closedSign)
        let exitSign = Mats.picture(Mats.label("EXIT", size: CGSize(width: 260, height: 100), font: 64, fg: 0xFFFFFF, bg: 0x1E8449, corner: 12))
        strip(SIMD2(dcx + 0.3, D - 0.008), SIMD2(dcx - 0.3, D - 0.008), 2.86, 3.09, exitSign)

        // ---- Shop windows either side of the door, with daylight outside
        let street = Mats.picture(Mats.streetView())
        let frameMat = Mats.solid(0x3F4852, gloss: 0.3)
        func window(_ xa: Float, _ xb: Float, _ u0: Float, _ u1: Float) {
            guard xb - xa > 1.2 else { return }
            let y0: Float = 1.08, y1: Float = 2.34, z = D - 0.012
            env.quad(SIMD3(xb, y0, z), SIMD3(xa, y0, z), SIMD3(xa, y1, z), SIMD3(xb, y1, z), street,
                     uv: (SIMD2(u0, 1), SIMD2(u1, 1), SIMD2(u1, 0), SIMD2(u0, 0)))
            let cx = (xa + xb) / 2, w = xb - xa
            env.box(cx, y0 - 0.03, D - 0.04, w + 0.12, 0.06, 0.1, frameMat)
            env.box(cx, y1 + 0.03, D - 0.03, w + 0.12, 0.06, 0.07, frameMat)
            env.box(xa - 0.03, (y0 + y1) / 2, D - 0.03, 0.06, y1 - y0, 0.07, frameMat)
            env.box(xb + 0.03, (y0 + y1) / 2, D - 0.03, 0.06, y1 - y0, 0.07, frameMat)
            let panes = max(1, Int((w / 1.15).rounded()))
            if panes > 1 {
                for i in 1..<panes {
                    env.box(xa + w * Float(i) / Float(panes), (y0 + y1) / 2, D - 0.03, 0.04, y1 - y0, 0.05, frameMat)
                }
            }
        }
        window(0.6, layout.doorMinX - 0.55, 0.52, 1.0)      // left window as seen from inside is at high x
        window(layout.doorMaxX + 0.55, W - 0.6, 0.0, 0.48)

        // ---- Posters on the side walls near the entrance
        let posters: [(String, String, UInt32, UInt32)] = [
            ("FRESH\nDEALS", "every single day", 0xC0392B, 0xFFFFFF),
            ("TEAM\nO-CREW", "tidy aisles, happy shoppers", 0x1F3A5F, 0xFFD54A),
        ]
        let pz = D - 2.0
        strip(SIMD2(0.012, pz + 0.42), SIMD2(0.012, pz - 0.42), 1.16, 2.28,
              Mats.picture(Mats.poster(posters[0].0, posters[0].1, bg: posters[0].2, fg: posters[0].3), lit: true))
        let pz2 = D - 1.1
        strip(SIMD2(W - 0.012, pz2 - 0.42), SIMD2(W - 0.012, pz2 + 0.42), 1.16, 2.28,
              Mats.picture(Mats.poster(posters[1].0, posters[1].1, bg: posters[1].2, fg: posters[1].3), lit: true))

        // ---- Store name across the back wall
        let nameW = min(W - 1.6, 4.4)
        let nameMat = Mats.picture(Mats.label(theme.name.uppercased(), size: CGSize(width: 1100, height: 100), font: 70,
                                              fg: 0xFFFFFF, bg: theme.trim, corner: 22))
        strip(SIMD2(W / 2 - nameW / 2, 0.012), SIMD2(W / 2 + nameW / 2, 0.012), 2.84, 2.84 + nameW * 100 / 1100, nameMat)

        // ---- Ceiling with light panels and vents
        let ceilMat = Mats.tiled("ceiling") { Mats.ceilingTiles() }
        let ct: Float = 1 / 0.6
        env.quad(SIMD3(0, H, 0), SIMD3(W, H, 0), SIMD3(W, H, D), SIMD3(0, H, D), ceilMat,
                 uv: (SIMD2(0, 0), SIMD2(W * ct, 0), SIMD2(W * ct, D * ct), SIMD2(0, D * ct)))
        let lightMat = Mats.glow(0xFFFDF4)
        let ventMat = Mats.solid(0x9CA3AA)
        var lx: Float = 1.5
        var col = 0
        while lx < W - 0.9 {
            var lz: Float = 1.5
            var row = 0
            while lz < D - 0.9 {
                let y = H - 0.012
                if (row + col) % 5 == 4 {
                    env.quad(SIMD3(lx - 0.3, y, lz - 0.3), SIMD3(lx + 0.3, y, lz - 0.3),
                             SIMD3(lx + 0.3, y, lz + 0.3), SIMD3(lx - 0.3, y, lz + 0.3), ventMat)
                } else {
                    env.quad(SIMD3(lx - 0.6, y, lz - 0.3), SIMD3(lx + 0.6, y, lz - 0.3),
                             SIMD3(lx + 0.6, y, lz + 0.3), SIMD3(lx - 0.6, y, lz + 0.3), lightMat)
                }
                lz += 2.4
                row += 1
            }
            lx += 2.4
            col += 1
        }

        // ---- Scenery by the entrance
        buildProps(props, theme: theme)

        if let shell = env.build() {
            Models.setCategory(shell, Models.categoryNoHit)
            shell.castsShadow = false
            scene.rootNode.addChildNode(shell)
        }
        if let stuff = props.build() {
            Models.setCategory(stuff, Models.categoryNoHit)
            scene.rootNode.addChildNode(stuff)
        }
        let worldRoot = scene.rootNode

        // ---- Lighting: soft overhead store light with real shadows under the shelving
        let ambient = SCNNode(); ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 520
        ambient.light!.color = UIColor(hex: 0xFFF8EE)
        worldRoot.addChildNode(ambient)
        let key = SCNNode(); key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 640
        key.light!.color = UIColor(hex: 0xFFFDF7)
        if display.shadows {
            key.light!.castsShadow = true
            key.light!.shadowMode = .forward
            key.light!.shadowMapSize = CGSize(width: 2048, height: 2048)
            key.light!.shadowSampleCount = 8
            key.light!.shadowRadius = 4
            key.light!.shadowColor = UIColor(white: 0, alpha: 0.36)
            key.light!.shadowBias = 3
            key.light!.maximumShadowDistance = 28
        }
        key.eulerAngles = SCNVector3(Float(-1.2), Float(0.45), Float(0))
        worldRoot.addChildNode(key)
        let fill = SCNNode(); fill.light = SCNLight()
        fill.light!.type = .directional
        fill.light!.intensity = 260
        fill.eulerAngles = SCNVector3(Float(-0.55), Float.pi + 0.5, Float(0))
        worldRoot.addChildNode(fill)

        // ---- Shelving and coolers
        for (i, spec) in layout.fixtures.enumerated() {
            let f = Fixture(index: i, spec: spec, shelfColor: theme.shelfColor, trim: theme.trim)
            fixtures.append(f)
            worldRoot.addChildNode(f.node)
        }

        let binSign = Models.billboardText("EXPIRED", color: .white, bg: UIColor(hex: 0xC0392B), width: 0.7, height: 0.18, fontSize: 60)
        binSign.position = SCNVector3(layout.bin.center.x, 1.25, layout.bin.center.y)
        binSign.geometry?.firstMaterial?.readsFromDepthBuffer = true
        binSign.castsShadow = false
        worldRoot.addChildNode(binSign)

        // ---- Player, camera, arms
        playerNode.simdPosition = SIMD3(playerPos.x, 0, playerPos.y)
        let cam = SCNCamera()
        cam.projectionDirection = .horizontal
        cam.fieldOfView = CGFloat(display.fieldOfView)
        cam.zNear = 0.05
        cam.zFar = 80
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, eyeHeight, 0)
        playerNode.addChildNode(cameraNode)
        let prefs = ProgressStore.shared.data
        let arms = FirstPersonRig(sleeve: theme.trim, glove: Cosmetics.glove(prefs.glove).color)
        arms.basketHolder.addChildNode(basketNode)
        cameraNode.addChildNode(arms.root)
        rig = arms
        basketColor = Cosmetics.basket(prefs.basket).color
        worldRoot.addChildNode(playerNode)
        worldRoot.addChildNode(highlightNode)
    }

    private func buildProps(_ b: MeshBuilder, theme: StoreTheme) {
        // Trash bin for expired stock
        let bin = layout.bin.center
        b.cylinder(bin.x, 0, bin.y, r0: 0.27, r1: 0.31, h: 0.85, Mats.solid(0x56636F, gloss: 0.25), segs: 18)
        b.cylinder(bin.x, 0.85, bin.y, r0: 0.33, h: 0.05, Mats.solid(0xC0392B, gloss: 0.3), segs: 18)
        b.cylinder(bin.x, 0.9, bin.y, r0: 0.12, h: 0.012, Mats.solid(0x1B1F24), segs: 12)

        // Checkout counter
        let c = layout.counter
        let cw = c.size.x, cd = c.size.y
        b.box(c.center.x, 0.45, c.center.y, cw, 0.9, cd, Mats.solid(Mats.shade(theme.trim, 0.7), gloss: 0.2))
        b.box(c.center.x, 0.08, c.center.y, cw + 0.02, 0.16, cd + 0.02, Mats.solid(0x23272E))
        b.box(c.center.x, 0.92, c.center.y, cw + 0.08, 0.04, cd + 0.08, Mats.solid(0xD9DEE2, gloss: 0.5))
        b.box(c.minX + cw * 0.3, 0.946, c.center.y, cw * 0.5, 0.012, cd * 0.62, Mats.solid(0x17191C, gloss: 0.3))   // belt
        let rx = c.maxX - 0.32
        b.box(rx, 1.0, c.center.y, 0.3, 0.12, 0.3, Mats.solid(0x2B3036, gloss: 0.3))                              // till
        b.box(rx, 1.17, c.center.y + 0.05, 0.05, 0.22, 0.05, Mats.solid(0x2B3036))
        b.box(rx, 1.36, c.center.y + 0.05, 0.34, 0.24, 0.03, Mats.solid(0x17191C, gloss: 0.4))                     // screen
        b.box(rx, 1.36, c.center.y + 0.033, 0.3, 0.2, 0.004, Mats.glow(0x7FD6FF))
        b.box(c.minX + cw * 0.68, 0.99, c.center.y - cd * 0.2, 0.09, 0.1, 0.13, Mats.solid(0x3A4048, gloss: 0.3))  // card reader

        // Stack of spare baskets
        let bs = layout.basketStack
        for i in 0..<6 {
            let shade = i % 2 == 0 ? 1.0 : 0.86
            b.box(bs.center.x, 0.05 + Float(i) * 0.075, bs.center.y, bs.size.x - 0.04, 0.07, bs.size.y - 0.04,
                  Mats.solid(Mats.shade(0xD62828, shade), gloss: 0.25))
        }

        // Pallet of unopened stock
        let p = layout.pallet
        let wood = Mats.solid(0xB58A5A)
        for dz in [Float(-0.36), 0, 0.36] { b.box(p.center.x, 0.05, p.center.y + dz, p.size.x, 0.1, 0.1, wood) }
        for dx in [Float(-0.36), -0.12, 0.12, 0.36] { b.box(p.center.x + dx, 0.115, p.center.y, 0.16, 0.03, p.size.y, wood) }
        let card = Mats.solid(0xC49A6C)
        let tape = Mats.solid(0xE6D6B0)
        func carton(_ x: Float, _ y: Float, _ z: Float, _ s: Float) {
            b.box(x, y, z, s, s * 0.78, s, card)
            b.box(x, y + s * 0.39 + 0.001, z, 0.07, 0.002, s, tape)
        }
        for (dx, dz) in [(Float(-0.21), Float(-0.21)), (0.21, -0.21), (-0.21, 0.21), (0.21, 0.21)] {
            carton(p.center.x + dx, 0.13 + 0.156, p.center.y + dz, 0.4)
        }
        b.transform = Models.translate(p.center.x - 0.05, 0.13 + 0.312 + 0.15, p.center.y + 0.04) * Models.rotate(0.4, SIMD3(0, 1, 0))
        carton(0, 0, 0, 0.38)
        b.transform = matrix_identity_float4x4

        // Potted plant by the door
        let pl = layout.plant.center
        b.cylinder(pl.x, 0, pl.y, r0: 0.13, r1: 0.18, h: 0.3, Mats.solid(0xB5653A, gloss: 0.15), segs: 14)
        b.cylinder(pl.x, 0.28, pl.y, r0: 0.165, h: 0.02, Mats.solid(0x3B2A1E), segs: 14)
        b.cylinder(pl.x, 0.3, pl.y, r0: 0.3, r1: 0.02, h: 0.55, Mats.solid(0x2E7D4F), segs: 9, cap: false)
        b.cylinder(pl.x, 0.55, pl.y, r0: 0.25, r1: 0.02, h: 0.5, Mats.solid(0x3A9460), segs: 9, cap: false)
        b.cylinder(pl.x, 0.82, pl.y, r0: 0.18, r1: 0.0, h: 0.42, Mats.solid(0x47A86E), segs: 9, cap: false)

        // Wet-floor sign
        let ws = layout.wetSign.center
        let yellow = Mats.solid(0xF2C40F, gloss: 0.3)
        let caution = Mats.picture(Mats.label("⚠️\nWET\nFLOOR", size: CGSize(width: 200, height: 300), font: 52, fg: 0x1B1B1B, bg: 0xF2C40F), lit: true)
        for s in [Float(1), Float(-1)] {
            b.transform = Models.translate(ws.x, 0, ws.y + s * 0.15) * Models.rotate(-s * 0.26, SIMD3(1, 0, 0))
            b.box(0, 0.32, 0, 0.32, 0.64, 0.02, yellow)
            b.quad(SIMD3(-s * 0.13, 0.1, s * 0.0115), SIMD3(s * 0.13, 0.1, s * 0.0115),
                   SIMD3(s * 0.13, 0.56, s * 0.0115), SIMD3(-s * 0.13, 0.56, s * 0.0115), caution)
        }
        b.transform = matrix_identity_float4x4
    }
}
