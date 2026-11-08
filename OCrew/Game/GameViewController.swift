import UIKit
import SceneKit
import SwiftUI
import Combine

final class GameViewController: UIViewController {
    let level: StoreLevel
    var onExit: (() -> Void)?
    var onRestartDay: (() -> Void)?

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

    init(level: StoreLevel) {
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
        scnView.antialiasingMode = .multisampling4X
        scnView.rendersContinuously = true
        scnView.isJitteringEnabled = false
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
            b.addAction(UIAction { [weak self] _ in
                guard let self = self else { return }
                self.world.useSkill(id, focus: self.focus)
            }, for: .touchUpInside)
        }

        wireWorld()
        applySettings(SettingsStore.shared.display)
        SettingsStore.shared.$display
            .receive(on: RunLoop.main)
            .sink { [weak self] d in self?.applySettings(d) }
            .store(in: &cancellables)

        if world.tutorialActive {
            hud.showToast("Welcome to \(level.name)!", style: .good)
        } else {
            hud.showToast("Day \(world.day) of \(level.days) — stock up, then flip the sign to OPEN", style: .info)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startLoop()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if presentedViewController == nil { stopLoop() }
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
        world?.refreshAllTags()
        if let link = displayLink { configureFrameRate(link) }
    }

    private func wireWorld() {
        world.onToast = { [weak self] text, style in self?.hud.showToast(text, style: style) }
        world.onOpenComputer = { [weak self] in self?.openComputer(priceFocus: nil) }
        world.onOpenPrice = { [weak self] id in self?.openComputer(priceFocus: id) }
        world.onRequestChange = { [weak self] req in self?.openChange(req) }
        world.onDayEnded = { [weak self] s in self?.openSummary(s) }
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

            // Focus: what's under the crosshair
            hitFrame += 1
            if hitFrame % 2 == 0 {
                focus = hitTarget(at: CGPoint(x: scnView.bounds.midX, y: scnView.bounds.midY))
                world.setHighlight(focus)
            }
            // Hold-to-repeat stocking
            if interactHeld, SettingsStore.shared.display.holdToRepeatStock, world.carried != nil,
               let f = focus, case .slot = f,
               world.time - interactHeldSince > 0.35, world.time - lastRepeat > 0.11 {
                lastRepeat = world.time
                world.interact(f)
            }
        }
        refreshHUD()

        fpsFrames += 1
        fpsTime += dt
        if fpsTime >= 0.5 {
            hud.fpsLabel.text = "\(Int(Double(fpsFrames) / fpsTime)) FPS"
            fpsFrames = 0
            fpsTime = 0
        }
    }

    private func hitTarget(at p: CGPoint) -> Target? {
        let opts: [SCNHitTestOption: Any] = [
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
            .categoryBitMask: Models.categoryWorld,
            .ignoreHiddenNodes: true,
        ]
        guard let hit = scnView.hitTest(p, options: opts).first else { return nil }
        return world.target(for: hit.node, hitPoint: hit.simdWorldCoordinates)
    }

    private func refreshHUD() {
        let d = SettingsStore.shared.display
        hud.setStatus(money: formatMoney(world.cash, symbol: d.currencySymbol),
                      day: "Day \(world.day)/\(level.days)  ·  \(world.queue.count) in line",
                      rating: world.rating, clock: world.clockString(), phase: world.phase)
        hud.setPrompt(world.prompt(for: focus))
        hud.setTip(world.tutorialText)
        hud.crosshair.focused = focus != nil
        let mul = world.skillMultiplier
        for (id, b) in hud.skillButtons {
            let frac = world.skills.cooldownFraction(id, now: world.time, multiplier: mul)
            b.cooldown = CGFloat(frac)
            b.active = world.skills.isActive(id, now: world.time)
            let rem = world.skills.remaining(id, now: world.time)
            b.countdown.text = rem > 0 ? "\(Int(ceil(rem)))" : nil
            b.icon.alpha = rem > 0 ? 0.35 : 1
        }
    }

    // MARK: Input

    private func tapWorld(at p: CGPoint) {
        guard !overlayOpen else { return }
        let t = hitTarget(at: p)
        if t == nil { return }
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
        let presenter = presentedViewController ?? self
        presenter.present(host, animated: true)
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
        presentOverlay(PauseView(
            levelName: level.name, day: world.day, totalDays: level.days,
            onResume: { [weak self] in self?.closeOverlay() },
            onSettings: { [weak self] in
                self?.closeOverlay { self?.openSettings() }
            },
            onHelp: { [weak self] in
                self?.closeOverlay { self?.openHelp() }
            },
            onRestartDay: { [weak self] in
                self?.closeOverlay { self?.onRestartDay?() }
            },
            onQuit: { [weak self] in
                self?.closeOverlay { self?.quit() }
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

    private func openComputer(priceFocus: String?) {
        guard !overlayOpen else { return }
        let model = ComputerModel(world: world, focusProduct: priceFocus)
        presentOverlay(ComputerView(model: model, onClose: { [weak self] in self?.closeOverlay() }))
    }

    private func openChange(_ req: ChangeRequest) {
        guard !overlayOpen else { return }
        presentOverlay(ChangeView(request: req, showDue: SettingsStore.shared.game.showChangeDue,
                           symbol: SettingsStore.shared.display.currencySymbol,
                           onGive: { [weak self] given in
                               self?.world.completeSale(given: given)
                               self?.closeOverlay()
                           },
                           onCancel: { [weak self] in self?.closeOverlay() }))
    }

    private func openSummary(_ s: DaySummary) {
        if overlayOpen {
            // Close whatever is open first (e.g. the computer) then show the summary.
            closeOverlay { [weak self] in self?.overlayOpen = false; self?.openSummary(s) }
            return
        }
        presentOverlay(SummaryView(summary: s, symbol: SettingsStore.shared.display.currencySymbol, onContinue: { [weak self] in
            guard let self = self else { return }
            if self.world.continueAfterSummary() {
                self.closeOverlay()
            } else {
                self.closeOverlay { self.onExit?() }
            }
        }))
    }

    private func quit() {
        stopLoop()
        onExit?()
    }

    /// Called when SwiftUI removes the game (quit, restart).
    func shutdown() {
        stopLoop()
        world?.paused = true
        cancellables.removeAll()
    }
}

/// SwiftUI wrapper.
@MainActor
struct GameContainer: UIViewControllerRepresentable {
    let level: StoreLevel
    let onExit: () -> Void
    let onRestartDay: () -> Void

    func makeUIViewController(context: Context) -> GameViewController {
        let vc = GameViewController(level: level)
        vc.onExit = onExit
        vc.onRestartDay = onRestartDay
        return vc
    }

    func updateUIViewController(_ vc: GameViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: GameViewController, coordinator: ()) {
        vc.shutdown()
    }
}
