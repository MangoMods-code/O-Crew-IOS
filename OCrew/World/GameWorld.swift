import SceneKit
import simd
import UIKit

struct CarryBox {
    var product: String
    var count: Int
}

final class FloorBox {
    let id: Int
    var product: String
    var count: Int
    let node: SCNNode
    var onPad: Bool
    init(id: Int, product: String, count: Int, node: SCNNode, onPad: Bool) {
        self.id = id; self.product = product; self.count = count; self.node = node; self.onPad = onPad
    }
}

struct BeltItem {
    let node: SCNNode
    let product: String
    var scanned: Bool
}

struct DayStats {
    var revenue = 0.0
    var expenses = 0.0
    var stockSpend = 0.0
    var served = 0
    var angry = 0
    var thefts = 0
    var caught = 0
    var stolenValue = 0.0
    var outOfStock = 0
    var tooExpensive = 0
    var unitsSold = 0
    var changeMistakes = 0
    var missing: [String: Int] = [:]
}

struct DaySummary {
    let levelName: String
    let day: Int
    let totalDays: Int
    let stats: DayStats
    let rent: Double
    let dayProfit: Double
    let levelProfit: Double
    let profitGoal: Double
    let rating: Double
    let ratingGoal: Double
    let cash: Double
    let isLastDay: Bool
    let passed: Bool
    let stars: Int
    let nextLevelName: String?
}

enum Phase { case prep, open, closing, ended }

enum Target: Equatable {
    case slot(Int, Int)
    case floorBox(Int)
    case beltItem(Int)
    case terminal, register, computer, sign, bin
    case customer(Int)
}

enum ToastStyle { case info, good, warn, bad }

struct ChangeRequest {
    let total: Double
    let tendered: Double
}

@MainActor
final class GameWorld {
    // MARK: Static setup
    let level: StoreLevel
    let layout: StoreLayout
    let nav: NavGrid
    let scene = SCNScene()
    let playerNode = SCNNode()
    let cameraNode = SCNNode()
    let carryNode = SCNNode()
    let highlightNode: SCNNode
    var signNode = SCNNode()
    var fixtures: [Fixture] = []
    var playerRects: [Rect] = []
    let eyeHeight: Float = 1.62

    // MARK: Player
    var playerPos: SIMD2<Float>
    var yaw: Float = 0
    var pitch: Float = -0.08
    var targetYaw: Float = 0
    var targetPitch: Float = -0.08
    var bobPhase: Float = 0
    var carried: CarryBox?

    // MARK: Store state
    var cash: Double = 0
    var rating: Double = 3.0
    var levelProfit: Double = 0
    var day: Int = 1
    var phase: Phase = .prep
    var clock: Double = 0              // 0..1 through opening hours
    var prices: [String: Double] = [:]
    var stats = DayStats()
    var floorBoxes: [FloorBox] = []
    var nextBoxID = 1
    var pending: [(at: Double, product: String)] = []
    var customers: [Customer] = []
    var nextCustomerID = 1
    var queue: [Customer] = []
    var belt: [BeltItem] = []
    var beltTotal: Double = 0
    var checkoutCustomer: Customer?
    var skills = SkillSet()
    var time: Double = 0
    var paused = false
    var rushAnnounced: Set<Int> = []
    var lastSummary: DaySummary?
    var deliveryToastPending = false

    // MARK: Tutorial
    var tutorialActive = false
    var tutorialStep = 0
    var stockedUnits = 0
    var ordersPlaced = 0

    // MARK: Callbacks to the view controller
    var onToast: ((String, ToastStyle) -> Void)?
    var onDayEnded: ((DaySummary) -> Void)?
    var onRequestChange: ((ChangeRequest) -> Void)?
    var onOpenPrice: ((String) -> Void)?
    var onOpenComputer: (() -> Void)?
    var onMoneyPopup: ((Double) -> Void)?

    var display: DisplaySettings { SettingsStore.shared.display }
    var game: GameSettings { SettingsStore.shared.game }
    var symbol: String { display.currencySymbol }

    // MARK: Init

    init(level: StoreLevel, save: LevelSave?) {
        self.level = level
        layout = StoreLayout(level: level)
        nav = NavGrid(layout: layout)
        playerPos = layout.playerStart

        let hl = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
        let hm = SCNMaterial()
        hm.diffuse.contents = UIColor(white: 1, alpha: 0.16)
        hm.emission.contents = UIColor(white: 1, alpha: 0.16)
        hm.lightingModel = .constant
        hm.writesToDepthBuffer = false
        hm.transparencyMode = .dualLayer
        hl.geometry?.firstMaterial = hm
        hl.categoryBitMask = Models.categoryNoHit
        hl.renderingOrder = 50
        hl.isHidden = true
        highlightNode = hl

        buildScene()
        playerRects = layout.solidRects + layout.playerOnlyRects

        if let s = save, s.slots.count == fixtures.count {
            day = s.day
            cash = s.cash
            rating = s.rating
            levelProfit = s.levelProfit
            prices = s.prices
            for (fi, fx) in fixtures.enumerated() {
                for (si, slot) in fx.slots.enumerated() where si < s.slots[fi].count {
                    slot.product = s.slots[fi][si].product
                    slot.count = s.slots[fi][si].count
                    slot.rebuild()
                }
            }
            for b in s.boxes { spawnPadBox(product: b.product, count: b.count) }
        } else {
            cash = (level.startingCash * game.startingCash).rounded()
            rating = 3.0
        }
        for id in level.products where prices[id] == nil {
            prices[id] = Catalog.product(id)?.market ?? 1
        }
        tutorialActive = level.number == 1 && day == 1 && game.showTutorial && !ProgressStore.shared.data.seenTutorial
        refreshAllTags()
        beginDay()
    }

    // MARK: Scene

    private func buildScene() {
        let W = layout.width, D = layout.depth
        let root = scene.rootNode

        // Floor
        let floor = SCNPlane(width: CGFloat(W), height: CGFloat(D))
        let fm = Models.imageMat(Models.checkerImage(level.floor, level.floorAlt, grout: level.floorAlt &- 0x101010))
        fm.diffuse.wrapS = .repeat
        fm.diffuse.wrapT = .repeat
        fm.diffuse.contentsTransform = SCNMatrix4MakeScale(W / 1.2, D / 1.2, 1)
        floor.firstMaterial = fm
        let floorNode = SCNNode(geometry: floor)
        floorNode.eulerAngles.x = -.pi / 2
        floorNode.position = SCNVector3(W / 2, 0, D / 2)
        root.addChildNode(floorNode)

        // Outside: sidewalk + street
        let walk = SCNNode(geometry: SCNPlane(width: CGFloat(W + 30), height: 4))
        walk.geometry?.firstMaterial = Models.mat(0xB8B8B0)
        walk.eulerAngles.x = -.pi / 2
        walk.position = SCNVector3(W / 2, -0.005, D + 2)
        root.addChildNode(walk)
        let street = SCNNode(geometry: SCNPlane(width: CGFloat(W + 60), height: 30))
        street.geometry?.firstMaterial = Models.mat(0x3D3F42)
        street.eulerAngles.x = -.pi / 2
        street.position = SCNVector3(W / 2, -0.02, D + 19)
        root.addChildNode(street)
        for i in 0..<12 {
            let line = Models.box(1.6, 0.01, 0.15, 0xF4D03F)
            line.position = SCNVector3(-6 + Float(i) * 4, -0.01, D + 10)
            root.addChildNode(line)
        }

        // Walls
        let H: Float = 3.2, t = layout.wallThickness
        func wall(_ x0: Float, _ z0: Float, _ x1: Float, _ z1: Float, _ h: Float, _ y: Float) {
            let w = max(0.01, x1 - x0), d = max(0.01, z1 - z0)
            let n = Models.box(w, h, d, level.wall)
            n.position = SCNVector3((x0 + x1) / 2, y + h / 2, (z0 + z1) / 2)
            root.addChildNode(n)
        }
        wall(-t, -t, W + t, 0, H, 0)
        wall(-t, 0, 0, D + t, H, 0)
        wall(W, 0, W + t, D + t, H, 0)
        wall(-t, D, layout.doorMinX, D + t, H, 0)
        wall(layout.doorMaxX, D, W + t, D + t, H, 0)
        wall(layout.doorMinX, D, layout.doorMaxX, D + t, H - 2.5, 2.5)
        // Trim stripes
        func trim(_ x0: Float, _ z0: Float, _ x1: Float, _ z1: Float, y: Float, h: Float) {
            let n = Models.box(max(0.01, x1 - x0), h, max(0.01, z1 - z0), level.trim)
            n.position = SCNVector3((x0 + x1) / 2, y, (z0 + z1) / 2)
            n.categoryBitMask = Models.categoryNoHit
            root.addChildNode(n)
        }
        for y in [Float(0.08), Float(2.45)] {
            let h: Float = y < 1 ? 0.16 : 0.22
            trim(0, 0, W, 0.02, y: y, h: h)
            trim(0, 0, 0.02, D, y: y, h: h)
            trim(W - 0.02, 0, W, D, y: y, h: h)
            trim(0, D - 0.02, layout.doorMinX, D, y: y, h: h)
            trim(layout.doorMaxX, D - 0.02, W, D, y: y, h: h)
        }
        // Front windows
        let winW = layout.doorMinX - 1.5
        if winW > 1 {
            for z in [D - 0.03, D + t + 0.03] {
                let win = SCNNode(geometry: SCNPlane(width: CGFloat(winW), height: 1.3))
                win.geometry?.firstMaterial = Models.emissive(0x9FC9E8)
                win.position = SCNVector3(0.75 + winW / 2, 1.55, z)
                win.categoryBitMask = Models.categoryNoHit
                if z > D { win.eulerAngles.y = 0 } else { win.eulerAngles.y = .pi }
                root.addChildNode(win)
            }
        }
        // Exterior store sign
        let storeSign = Models.billboardText(level.name.uppercased(), color: .white, bg: UIColor(hex: level.trim), width: 5, height: 0.7, fontSize: 120)
        storeSign.constraints = nil
        storeSign.position = SCNVector3(W / 2, 2.85, D + t + 0.05)
        root.addChildNode(storeSign)

        // Ceiling + light panels
        let ceil = SCNNode(geometry: SCNPlane(width: CGFloat(W), height: CGFloat(D)))
        ceil.geometry?.firstMaterial = Models.mat(0xF2F2EE)
        ceil.eulerAngles.x = .pi / 2
        ceil.position = SCNVector3(W / 2, H, D / 2)
        ceil.categoryBitMask = Models.categoryNoHit
        root.addChildNode(ceil)
        var lx: Float = 2
        while lx < W - 1 {
            var lz: Float = 2
            while lz < D - 1 {
                let panel = SCNNode(geometry: SCNPlane(width: 1.2, height: 0.5))
                panel.geometry?.firstMaterial = Models.emissive(0xFFFDF2)
                panel.eulerAngles.x = .pi / 2
                panel.position = SCNVector3(lx, H - 0.01, lz)
                panel.categoryBitMask = Models.categoryNoHit
                root.addChildNode(panel)
                lz += 3
            }
            lx += 3
        }

        // Lights
        let ambient = SCNNode(); ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 520
        ambient.light!.color = UIColor(hex: 0xFFF8EE)
        root.addChildNode(ambient)
        let sun = SCNNode(); sun.light = SCNLight()
        sun.light!.type = .directional
        sun.light!.intensity = 620
        sun.light!.color = UIColor(hex: 0xFFFFFF)
        sun.eulerAngles = SCNVector3(-1.05, 0.55, 0)
        root.addChildNode(sun)
        let fill = SCNNode(); fill.light = SCNLight()
        fill.light!.type = .directional
        fill.light!.intensity = 220
        fill.eulerAngles = SCNVector3(-0.6, .pi + 0.4, 0)
        root.addChildNode(fill)

        // Fixtures
        for (i, spec) in layout.fixtures.enumerated() {
            let f = Fixture(index: i, spec: spec, shelfColor: level.shelfColor)
            fixtures.append(f)
            root.addChildNode(f.node)
        }

        buildCounter(root)
        buildDesk(root)

        // Delivery pad
        let padImg = Models.stripesImage(0xF4D03F, 0x2C2C2C)
        let pad = SCNNode(geometry: SCNPlane(width: CGFloat(layout.pad.size.x), height: CGFloat(layout.pad.size.y)))
        let pm = Models.imageMat(padImg)
        pm.diffuse.wrapS = .repeat; pm.diffuse.wrapT = .repeat
        pm.diffuse.contentsTransform = SCNMatrix4MakeScale(layout.pad.size.x * 1.5, layout.pad.size.y * 1.5, 1)
        pad.geometry?.firstMaterial = pm
        pad.eulerAngles.x = -.pi / 2
        pad.position = SCNVector3(layout.pad.center.x, 0.004, layout.pad.center.y)
        pad.categoryBitMask = Models.categoryNoHit
        root.addChildNode(pad)
        let padLabel = Models.billboardText("DELIVERIES", color: .black, bg: UIColor(hex: 0xF4D03F), width: 1.2, height: 0.25, fontSize: 60)
        padLabel.position = SCNVector3(layout.pad.center.x, 2.2, layout.pad.minZ)
        root.addChildNode(padLabel)

        // Bin
        let bin = SCNNode()
        bin.name = "bin"
        let can = SCNNode(geometry: SCNCylinder(radius: 0.3, height: 0.85))
        can.geometry?.firstMaterial = Models.mat(0x566573)
        can.position.y = 0.425
        bin.addChildNode(can)
        let lid = SCNNode(geometry: SCNCylinder(radius: 0.32, height: 0.05))
        lid.geometry?.firstMaterial = Models.mat(0x2E4053)
        lid.position.y = 0.87
        bin.addChildNode(lid)
        bin.position = SCNVector3(layout.bin.center.x, 0, layout.bin.center.y)
        root.addChildNode(bin)

        // Open/closed sign over the door (faces into the store)
        let sign = SCNNode()
        sign.name = "sign"
        let board = SCNNode(geometry: SCNBox(width: 1.0, height: 0.4, length: 0.05, chamferRadius: 0.02))
        board.geometry?.firstMaterial = Models.mat(0x1B1F24)
        sign.addChildNode(board)
        let face = SCNNode(geometry: SCNPlane(width: 0.92, height: 0.32))
        face.name = "signFace"
        face.geometry?.firstMaterial = SCNMaterial()
        face.geometry?.firstMaterial?.lightingModel = .constant
        face.position.z = 0.03
        sign.addChildNode(face)
        sign.position = SCNVector3(layout.doorCenterX, 2.25, D - 0.12)
        sign.eulerAngles.y = .pi
        root.addChildNode(sign)
        signNode = sign
        updateSign()

        // Player
        playerNode.simdPosition = SIMD3(playerPos.x, 0, playerPos.y)
        let cam = SCNCamera()
        cam.projectionDirection = .horizontal
        cam.fieldOfView = CGFloat(display.fieldOfView)
        cam.zNear = 0.05
        cam.zFar = 120
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, eyeHeight, 0)
        playerNode.addChildNode(cameraNode)
        carryNode.position = SCNVector3(0.3, -0.48, -0.78)
        carryNode.eulerAngles = SCNVector3(0.12, -0.18, 0)
        cameraNode.addChildNode(carryNode)
        root.addChildNode(playerNode)
        root.addChildNode(highlightNode)
    }

    private func buildCounter(_ root: SCNNode) {
        let c = layout.counter
        let base = Models.box(c.size.x, 0.92, c.size.y, 0x5D4037, chamfer: 0.02)
        base.position = SCNVector3(c.center.x, 0.46, c.center.y)
        root.addChildNode(base)
        let top = Models.box(c.size.x + 0.06, 0.04, c.size.y + 0.06, 0xD7CCC8)
        top.position = SCNVector3(c.center.x, 0.94, c.center.y)
        root.addChildNode(top)
        let beltNode = Models.box(0.6, 0.012, 1.3, 0x1C1C1C)
        beltNode.position = SCNVector3(c.center.x + 0.05, 0.966, c.minZ + 0.85)
        beltNode.categoryBitMask = Models.categoryNoHit
        root.addChildNode(beltNode)
        let scanner = Models.box(0.3, 0.01, 0.2, 0x7FB3D5)
        scanner.geometry?.firstMaterial = Models.emissive(0x5DADE2)
        scanner.position = SCNVector3(c.center.x, 0.966, c.maxZ - 0.75)
        scanner.categoryBitMask = Models.categoryNoHit
        root.addChildNode(scanner)

        // Register (cash drawer + screen)
        let reg = SCNNode()
        reg.name = "register"
        let drawer = Models.box(0.45, 0.14, 0.4, 0x2C3E50, chamfer: 0.01)
        drawer.position.y = 0.07
        reg.addChildNode(drawer)
        let screen = SCNNode(geometry: SCNBox(width: 0.3, height: 0.2, length: 0.03, chamferRadius: 0.01))
        screen.geometry?.materials = [Models.emissive(0x48C9B0), Models.mat(0x1C2833), Models.mat(0x1C2833),
                                      Models.mat(0x1C2833), Models.mat(0x1C2833), Models.mat(0x1C2833)]
        screen.position = SCNVector3(0, 0.3, 0)
        screen.eulerAngles.y = -.pi / 2
        reg.addChildNode(screen)
        reg.position = SCNVector3(c.minX + 0.22, 0.96, c.maxZ - 0.3)
        root.addChildNode(reg)

        // Card terminal
        let term = SCNNode()
        term.name = "terminal"
        let body = Models.box(0.12, 0.2, 0.08, 0x17202A, chamfer: 0.01)
        body.position.y = 0.1
        term.addChildNode(body)
        let tScreen = SCNNode(geometry: SCNPlane(width: 0.08, height: 0.07))
        tScreen.geometry?.firstMaterial = Models.emissive(0x58D68D)
        tScreen.position = SCNVector3(0.061, 0.15, 0)
        tScreen.eulerAngles.y = .pi / 2
        term.addChildNode(tScreen)
        term.position = SCNVector3(c.maxX - 0.15, 0.96, c.minZ + 0.25)
        root.addChildNode(term)
    }

    private func buildDesk(_ root: SCNNode) {
        let d = layout.desk
        let comp = SCNNode()
        comp.name = "computer"
        let desk = Models.box(d.size.x, 0.75, d.size.y, 0x8D6E63)
        desk.position = SCNVector3(0, 0.375, 0)
        comp.addChildNode(desk)
        let monitor = SCNNode(geometry: SCNBox(width: 0.05, height: 0.38, length: 0.62, chamferRadius: 0.01))
        monitor.geometry?.materials = [Models.mat(0x111111), Models.emissive(0x3498DB), Models.mat(0x111111),
                                       Models.mat(0x111111), Models.mat(0x111111), Models.mat(0x111111)]
        monitor.position = SCNVector3(0.0, 1.0, 0)
        comp.addChildNode(monitor)
        let stand = Models.box(0.05, 0.22, 0.05, 0x222222)
        stand.position = SCNVector3(0, 0.82, 0)
        comp.addChildNode(stand)
        let kb = Models.box(0.18, 0.02, 0.45, 0x2C2C2C)
        kb.position = SCNVector3(0.18, 0.76, 0)
        comp.addChildNode(kb)
        comp.position = SCNVector3(d.center.x, 0, d.center.y)
        root.addChildNode(comp)
    }

    func updateSign() {
        guard let face = signNode.childNode(withName: "signFace", recursively: false) else { return }
        let open = phase == .open
        face.geometry?.firstMaterial?.diffuse.contents = Models.textImage(
            open ? "OPEN" : "CLOSED", size: CGSize(width: 368, height: 128),
            font: .systemFont(ofSize: 84, weight: .black),
            color: .white, bg: UIColor(hex: open ? 0x1E8449 : 0xB03A2E), corner: 16)
    }

    // MARK: Per-frame

    func look(dx: Float, dy: Float) {
        let s = Float(display.lookSensitivity) * 0.0055
        let sy = s * Float(display.lookSensitivityY) * (display.invertY ? -1 : 1)
        targetYaw -= dx * s
        targetPitch = max(-1.35, min(1.35, targetPitch - dy * sy))
    }

    func update(dt rawDt: Double, move: SIMD2<Float>) {
        guard !paused else { return }
        let dt = min(rawDt, 0.05)
        time += dt
        updatePlayer(dt: Float(dt), move: move)
        updateDeliveries()
        updateClock(dt: dt)
        updateCustomers(dt: Float(dt))
        updateTutorial()
        if phase == .closing && customers.isEmpty { endDay() }
    }

    private func updatePlayer(dt: Float, move: SIMD2<Float>) {
        let d = display
        let s = Float(d.cameraSmoothing)
        let k: Float = s < 0.02 ? 1 : 1 - pow(s, dt * 30)
        yaw += (targetYaw - yaw) * k
        pitch += (targetPitch - pitch) * k
        playerNode.simdEulerAngles = SIMD3(0, yaw, 0)

        var mv = move
        let len = simd_length(mv)
        if len > 1 { mv /= len }
        let sprinting = skills.isActive(.sprint, now: time)
        let speed: Float = 3.0 * Float(game.walkSpeed) * (sprinting ? 1.8 : 1)
        let forward = SIMD2<Float>(-sin(yaw), -cos(yaw))
        let right = SIMD2<Float>(cos(yaw), -sin(yaw))
        let p = playerPos + (forward * mv.y + right * mv.x) * speed * dt
        playerPos = resolveCollisions(p)
        playerNode.simdPosition = SIMD3(playerPos.x, 0, playerPos.y)

        let moving = simd_length(mv) > 0.08
        if moving { bobPhase += dt * speed * 3.4 }
        let bob: Float = (d.headBob && !d.reduceMotion && moving) ? sin(bobPhase) * 0.032 * min(1, simd_length(mv)) : 0
        cameraNode.simdPosition = SIMD3(0, eyeHeight + bob, 0)
        cameraNode.simdEulerAngles = SIMD3(pitch, 0, 0)
        cameraNode.camera?.fieldOfView = CGFloat(d.fieldOfView)
    }

    func resolveCollisions(_ p: SIMD2<Float>) -> SIMD2<Float> {
        var q = p
        let r: Float = 0.28
        for _ in 0..<2 {
            for rect in playerRects {
                let cx = max(rect.minX, min(q.x, rect.maxX))
                let cz = max(rect.minZ, min(q.y, rect.maxZ))
                let d = q - SIMD2(cx, cz)
                let dist = simd_length(d)
                if dist >= r { continue }
                if dist > 1e-4 {
                    q = SIMD2(cx, cz) + d / dist * r
                } else {
                    let l = q.x - rect.minX, rr = rect.maxX - q.x, t = q.y - rect.minZ, b = rect.maxZ - q.y
                    let m = min(l, rr, t, b)
                    if m == l { q.x = rect.minX - r } else if m == rr { q.x = rect.maxX + r }
                    else if m == t { q.y = rect.minZ - r } else { q.y = rect.maxZ + r }
                }
            }
        }
        return q
    }

    private func updateClock(dt: Double) {
        guard phase == .open else { return }
        clock += dt / max(60, game.dayLengthMinutes * 60)
        let minutes = 8 * 60 + clock * 720
        for (start, label) in [(720.0, "Lunch rush!"), (1020.0, "After-work rush!")] {
            let key = Int(start)
            if minutes >= start && minutes < start + 60 && !rushAnnounced.contains(key) {
                rushAnnounced.insert(key)
                toast(label, .warn)
            }
        }
        if clock >= 1 {
            clock = 1
            beginClosing(early: false)
            return
        }
        trySpawn(dt: dt, minutes: minutes)
    }

    // MARK: Focus helpers

    var cameraWorldPosition: SIMD3<Float> { cameraNode.simdWorldPosition }

    func target(for node: SCNNode, hitPoint: SIMD3<Float>) -> Target? {
        var n: SCNNode? = node
        while let cur = n {
            if let name = cur.name, let t = parseTarget(name) {
                let dist = simd_distance(hitPoint, cameraWorldPosition)
                if case .customer = t { return dist <= 4.0 ? t : nil }
                return dist <= 2.6 ? t : nil
            }
            n = cur.parent
        }
        return nil
    }

    private func parseTarget(_ name: String) -> Target? {
        let parts = name.split(separator: ":")
        let head = parts.first.map { String($0) } ?? ""
        switch head {
        case "slot": if parts.count == 3, let f = Int(parts[1]), let s = Int(parts[2]) { return .slot(f, s) }
        case "fbox": if parts.count == 2, let i = Int(parts[1]) { return .floorBox(i) }
        case "belt": if parts.count == 2, let i = Int(parts[1]) { return .beltItem(i) }
        case "cust": if parts.count == 2, let i = Int(parts[1]) { return .customer(i) }
        case "terminal": return .terminal
        case "register": return .register
        case "computer": return .computer
        case "sign": return .sign
        case "bin": return .bin
        default: break
        }
        return nil
    }

    func node(for t: Target) -> SCNNode? {
        switch t {
        case let .slot(f, s): return fixtures[safe: f]?.slots[safe: s]?.hitNode
        case let .floorBox(id): return floorBoxes.first { $0.id == id }?.node
        case let .beltItem(i): return belt[safe: i]?.node
        case .customer: return nil
        case .terminal: return scene.rootNode.childNode(withName: "terminal", recursively: false)
        case .register: return scene.rootNode.childNode(withName: "register", recursively: false)
        case .computer: return scene.rootNode.childNode(withName: "computer", recursively: false)
        case .sign: return signNode
        case .bin: return scene.rootNode.childNode(withName: "bin", recursively: false)
        }
    }

    func setHighlight(_ t: Target?) {
        guard display.highlightFocused, let t = t, let n = node(for: t) else {
            highlightNode.isHidden = true
            return
        }
        let (mn, mx) = n.boundingBox
        let center = SIMD3<Float>((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, (mn.z + mx.z) / 2)
        let size = SIMD3<Float>(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z) * 1.04 + 0.01
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(center, 1)
        var sc = matrix_identity_float4x4
        sc.columns.0.x = size.x; sc.columns.1.y = size.y; sc.columns.2.z = size.z
        highlightNode.simdTransform = n.simdWorldTransform * m * sc
        let pulse = 0.12 + 0.06 * sin(time * 5)
        highlightNode.geometry?.firstMaterial?.diffuse.contents = UIColor(white: 1, alpha: CGFloat(pulse))
        highlightNode.isHidden = false
    }

    // MARK: Feedback helpers

    func toast(_ text: String, _ style: ToastStyle = .info) {
        onToast?(text, style)
    }

    func popup(_ text: String, at p: SIMD3<Float>, color: UInt32) {
        let n = Models.billboardText(text, color: .white, bg: UIColor(hex: color, alpha: 0.85), width: Float(max(0.5, Double(text.count) * 0.09)), height: 0.2, fontSize: 56)
        n.simdPosition = p
        scene.rootNode.addChildNode(n)
        let rise = SCNAction.moveBy(x: 0, y: 0.6, z: 0, duration: 1.4)
        rise.timingMode = .easeOut
        n.runAction(.sequence([.group([rise, .sequence([.wait(duration: 0.9), .fadeOut(duration: 0.5)])]), .removeFromParentNode()]))
    }

    func refreshAllTags() {
        let show = display.showPriceTags
        for f in fixtures {
            for s in f.slots {
                s.refreshTag(price: s.product.flatMap { prices[$0] }, symbol: symbol, visible: show)
            }
        }
    }

    func refreshTags(for product: String) {
        let show = display.showPriceTags
        for f in fixtures {
            for s in f.slots where s.product == product {
                s.refreshTag(price: prices[product], symbol: symbol, visible: show)
            }
        }
    }

    func clockString() -> String {
        let minutes = Int(8 * 60 + clock * 720)
        let h = minutes / 60, m = (minutes % 60) / 5 * 5
        if display.use24hClock { return String(format: "%02d:%02d", h, m) }
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", h12, m, h < 12 ? "AM" : "PM")
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
