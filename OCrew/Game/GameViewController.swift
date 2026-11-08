import UIKit
import SceneKit
import SwiftUI
import Combine

final class GameViewController: UIViewController {
    let level: OrgLevel
    var onExit: (() -> Void)?
    var onRestart: (() -> Void)?
    var onNext: ((OrgLevel) -> Void)?

    private var world: GameWorld!
    private let scnView = SCNView()
    private let controls = ControlsView()
    private let hud = HUDView()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var focus: Target?
    private var interactHeld = false
    private var interactHeldSince: Double = 0
    private var lastRepeat: Double = 0
    private var fpsFrames = 0
    private var fpsTime: CFTimeInterval = 0
    private var overlayOpen = false
    private var cancellables = Set<AnyCancellable>()
    private var hitFrame = 0
    private var lastSave: Double = 0

    init(level: OrgLevel) {
        self.level = level
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        world = GameWorld(level: level, save: ProgressStore.shared.save(for: level.id))

        scnView.frame = view.bounds
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.scene = world.scene
        scnView.pointOfView = world.cameraNode
        scnView.backgroundColor = UIColor(hex: 0x9CC9EA)
        // Render at 2x instead of the phone's native 3x and with lighter anti-aliasing:
        // ~2.25x fewer pixels for the GPU, and the difference is hard to see on a phone.
        scnView.contentScaleFactor = min(2, UIScreen.main.scale)
        scnView.antialiasingMode = .multisampling2X
        scnView.rendersContinuously = true
        view.addSubview(scnView)

        controls.frame = view.bounds
        controls.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controls)
        hud.frame = view.bounds
        hud.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hud)

        controls.onTap = { [weak self] p in self?.tapWorld(at: p) }
        hud.pauseButton.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)
        hud.interactButton.addTarget(self, action: #selector(interactDown), for: .touchDown)
        hud.interactButton.addTarget(self, action: #selector(interactUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        hud.dropButton.addTarget(self, action: #selector(dropTapped), for: .touchUpInside)
        for (id, b) in hud.skillButtons {
            b.addAction(UIAction { [weak self] _ in self?.world.useSkill(id) }, for: .touchUpInside)
        }
        hud.basketBar.onSelect = { [weak self] key in self?.world.select(key) }

        world.onToast = { [weak self] text, style in self?.hud.showToast(text, style: style) }
        world.onBasketChanged = { [weak self] in self?.refreshBasket() }
        world.onComplete = { [weak self] r in self?.showComplete(r) }

        applySettings(SettingsStore.shared.display)
        SettingsStore.shared.$display
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] d in self?.applySettings(d) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.world.snapshot() }
            .store(in: &cancellables)

        refreshBasket()
        hud.showToast("\(level.title) — \(level.stageName). Put every item back where it belongs!", style: .info)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startLoop()
    }

    private func startLoop() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        configureFrameRate(link)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTimestamp = 0
    }

    private func stopLoop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func configureFrameRate(_ link: CADisplayLink) {
        let fps = Float(SettingsStore.shared.display.frameRate.rawValue)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, fps), maximum: fps, preferred: fps)
        scnView.preferredFramesPerSecond = Int(fps)
    }

    private func applySettings(_ d: DisplaySettings) {
        hud.apply(d)
        controls.apply(d)
        scnView.showsStatistics = d.perfStats
        world?.refreshSigns()
        world?.refreshTags()
        if let link = displayLink { configureFrameRate(link) }
        refreshBasket()
    }

    private func refreshBasket() {
        guard let w = world else { return }
        hud.basketBar.update(groups: w.basketGroups, selected: w.selectedKey, used: w.basket.count, capacity: w.capacity)
        hud.setNeedsLayout()
    }

    // MARK: Loop

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTimestamp == 0 ? 1.0 / 60 : now - lastTimestamp
        lastTimestamp = now

        if !overlayOpen {
            let look = controls.consumeLook()
            world.look(dx: Float(look.x), dy: Float(look.y))
            world.update(dt: dt, move: controls.moveVector)

            focus = centerTarget()
            world.setHighlight(focus)
            // Hold the hand button to keep grabbing / placing
            if interactHeld, SettingsStore.shared.display.holdToRepeat, let f = focus,
               world.time - interactHeldSince > 0.3, world.time - lastRepeat > 0.12 {
                lastRepeat = world.time
                world.interact(f)
            }
            if world.time - lastSave > 45 {
                lastSave = world.time
                world.snapshot()
            }
        }
        let rem = world.remaining
        hud.setStatus(level: "\(level.title) · \(level.stageName)", time: world.timeString(),
                      frozen: world.skills.isActive(.freeze, now: world.time),
                      remaining: rem, progress: world.total > 0 ? 1 - Double(rem) / Double(world.total) : 1)
        hud.setPrompt(world.prompt(for: focus))
        hud.setTip(world.tutorialText)
        hud.crosshair.isTargeting = focus != nil
        let mul = world.skillMultiplier
        for (id, b) in hud.skillButtons {
            let cd = (CGFloat(world.skills.cooldownFraction(id, now: world.time, multiplier: mul)) * 60).rounded() / 60
            if b.cooldown != cd { b.cooldown = cd }
            let active = world.skills.isActive(id, now: world.time)
            if b.active != active { b.active = active }
            let rem = world.skills.remaining(id, now: world.time)
            let text: String? = rem > 0 ? "\(Int(ceil(rem)))" : nil
            if b.countdown.text != text { b.countdown.text = text }
            let a: CGFloat = rem > 0 ? 0.35 : 1
            if b.icon.alpha != a { b.icon.alpha = a }
        }

        fpsFrames += 1
        fpsTime += dt
        if fpsTime >= 0.5 {
            hud.fpsLabel.text = "\(Int(Double(fpsFrames) / fpsTime)) FPS"
            fpsFrames = 0
            fpsTime = 0
        }
    }

    private func hitTarget(at p: CGPoint) -> Target? {
        let a = scnView.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 0))
        let b = scnView.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 1))
        let o = SIMD3<Float>(a.x, a.y, a.z)
        return world.raycast(origin: o, dir: SIMD3<Float>(b.x, b.y, b.z) - o)
    }

    /// What the crosshair is on: a ray straight out of the camera.
    private func centerTarget() -> Target? {
        let cam = world.cameraNode
        return world.raycast(origin: cam.simdWorldPosition, dir: cam.simdWorldFront)
    }

    // MARK: Input

    private func tapWorld(at p: CGPoint) {
        guard !overlayOpen, let t = hitTarget(at: p) else { return }
        world.interact(t)
    }

    @objc private func interactDown() {
        interactHeld = true
        interactHeldSince = world.time
        world.interact(focus)
    }

    @objc private func interactUp() { interactHeld = false }

    @objc private func dropTapped() { world.secondary(focus) }

    @objc private func pauseTapped() { openPause() }

    // MARK: Overlays

    private func presentOverlay<V: View>(_ content: V) {
        overlayOpen = true
        world.paused = true
        interactHeld = false
        controls.reset()
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle = .crossDissolve
        present(host, animated: true)
    }

    private func closeOverlay(then next: (() -> Void)? = nil) {
        dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            if let next = next {
                next()
            } else {
                self.overlayOpen = false
                self.world.paused = false
                self.lastTimestamp = 0
            }
        }
    }

    private func openPause() {
        guard !overlayOpen else { return }
        world.snapshot()
        presentOverlay(PauseView(
            title: "\(level.title) · \(level.stageName)",
            subtitle: "\(world.remaining) items left · \(world.timeString())",
            onResume: { [weak self] in self?.closeOverlay() },
            onSettings: { [weak self] in self?.closeOverlay { self?.openSettings() } },
            onHelp: { [weak self] in self?.closeOverlay { self?.openHelp() } },
            onRestart: { [weak self] in
                self?.closeOverlay {
                    ProgressStore.shared.clearSave(self?.level.id ?? "")
                    self?.shutdown()
                    self?.onRestart?()
                }
            },
            onQuit: { [weak self] in
                self?.closeOverlay {
                    self?.world.snapshot()
                    self?.shutdown()
                    self?.onExit?()
                }
            }))
    }

    private func openSettings() {
        presentOverlay(SettingsView(inGame: true, onClose: { [weak self] in
            self?.closeOverlay { self?.overlayOpen = false; self?.openPause() }
        }))
    }

    private func openHelp() {
        presentOverlay(HowToPlayView(onClose: { [weak self] in
            self?.closeOverlay { self?.overlayOpen = false; self?.openPause() }
        }))
    }

    private func showComplete(_ r: LevelResult) {
        // Let the sparkles play for a moment first.
        interactHeld = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self = self else { return }
            if self.overlayOpen {
                self.dismiss(animated: false) { self.overlayOpen = false; self.showCompleteNow(r) }
            } else {
                self.showCompleteNow(r)
            }
        }
    }

    private func showCompleteNow(_ r: LevelResult) {
        do {
            self.presentOverlay(LevelCompleteView(
                result: r,
                onNext: r.next == nil ? nil : { [weak self] in
                    self?.closeOverlay {
                        self?.shutdown()
                        if let n = r.next { self?.onNext?(n) }
                    }
                },
                onReplay: { [weak self] in
                    self?.closeOverlay { self?.shutdown(); self?.onRestart?() }
                },
                onMenu: { [weak self] in
                    self?.closeOverlay { self?.shutdown(); self?.onExit?() }
                }))
        }
    }

    /// Stops the render loop (also called when SwiftUI removes the game).
    func shutdown() {
        stopLoop()
        world?.paused = true
        cancellables.removeAll()
    }
}

/// SwiftUI wrapper.
@MainActor
struct GameContainer: UIViewControllerRepresentable {
    let level: OrgLevel
    let onExit: () -> Void
    let onRestart: () -> Void
    let onNext: (OrgLevel) -> Void

    func makeUIViewController(context: Context) -> GameViewController {
        let vc = GameViewController(level: level)
        vc.onExit = onExit
        vc.onRestart = onRestart
        vc.onNext = onNext
        return vc
    }

    func updateUIViewController(_ vc: GameViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: GameViewController, coordinator: ()) {
        vc.shutdown()
    }
}
