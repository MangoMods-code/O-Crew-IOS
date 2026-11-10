import UIKit

/// Round button with an SF Symbol, optional caption and a cooldown pie.
final class RoundButton: UIControl {
    let icon = UIImageView()
    let caption = UILabel()
    let countdown = UILabel()
    private let pie = CAShapeLayer()
    private let ring = CAShapeLayer()
    var cooldown: CGFloat = 0 { didSet { if cooldown != oldValue { setNeedsLayout() } } }
    var active = false { didSet { ring.isHidden = !active } }
    var accent: UIColor = UIColor(hex: Theme.brand)

    init(symbol: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.08, alpha: 0.55)
        layer.borderColor = UIColor(white: 1, alpha: 0.35).cgColor
        layer.borderWidth = 1.5
        icon.image = UIImage(systemName: symbol)
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.isUserInteractionEnabled = false
        addSubview(icon)
        pie.fillColor = UIColor.clear.cgColor
        pie.strokeColor = UIColor(white: 0, alpha: 0.6).cgColor
        layer.addSublayer(pie)
        ring.fillColor = UIColor.clear.cgColor
        ring.lineWidth = 3
        ring.isHidden = true
        layer.addSublayer(ring)
        countdown.textColor = .white
        countdown.textAlignment = .center
        countdown.isUserInteractionEnabled = false
        addSubview(countdown)
        caption.textColor = .white
        caption.textAlignment = .center
        caption.isUserInteractionEnabled = false
        caption.shadowColor = UIColor(white: 0, alpha: 0.9)   // cheap text shadow (no offscreen pass)
        caption.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(caption)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { transform = isHighlighted ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = bounds.width
        layer.cornerRadius = s / 2
        icon.frame = bounds.insetBy(dx: s * 0.27, dy: s * 0.27)
        let r = s / 4
        pie.path = UIBezierPath(arcCenter: CGPoint(x: s / 2, y: s / 2), radius: r, startAngle: -.pi / 2,
                                endAngle: 1.5 * .pi, clockwise: true).cgPath
        pie.lineWidth = r * 2
        pie.strokeEnd = cooldown
        pie.frame = bounds
        ring.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5)).cgPath
        ring.strokeColor = accent.cgColor
        ring.frame = bounds
        countdown.frame = bounds
        caption.frame = CGRect(x: -20, y: s + 1, width: s + 40, height: 14)
    }
}

/// Crosshair drawn to match the display settings.
final class CrosshairView: UIView {
    var style: CrosshairStyle = .dot { didSet { setNeedsDisplay() } }
    var color: UIColor = .white { didSet { setNeedsDisplay() } }
    var isTargeting = false { didSet { if isTargeting != oldValue { setNeedsDisplay() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        let mid = CGPoint(x: bounds.midX, y: bounds.midY)
        let s = bounds.width / 2
        c.setShadow(offset: .zero, blur: 2, color: UIColor.black.withAlphaComponent(0.8).cgColor)
        color.setFill(); color.setStroke()
        let grow: CGFloat = isTargeting ? 1.35 : 1
        switch style {
        case .dot:
            let r = s * 0.22 * grow
            c.fillEllipse(in: CGRect(x: mid.x - r, y: mid.y - r, width: r * 2, height: r * 2))
        case .cross:
            c.setLineWidth(2)
            let a = s * 0.75 * grow, g = s * 0.22
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                c.move(to: CGPoint(x: mid.x + CGFloat(dx) * g, y: mid.y + CGFloat(dy) * g))
                c.addLine(to: CGPoint(x: mid.x + CGFloat(dx) * a, y: mid.y + CGFloat(dy) * a))
            }
            c.strokePath()
        case .circle:
            c.setLineWidth(2)
            let r = s * 0.55 * grow
            c.strokeEllipse(in: CGRect(x: mid.x - r, y: mid.y - r, width: r * 2, height: r * 2))
            c.fillEllipse(in: CGRect(x: mid.x - 1.5, y: mid.y - 1.5, width: 3, height: 3))
        case .none:
            break
        }
    }
}

/// Small rounded label with padding.
final class PillLabel: UILabel {
    var insets = UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + insets.left + insets.right, height: s.height + insets.top + insets.bottom)
    }
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let inner = CGSize(width: size.width - insets.left - insets.right, height: size.height - insets.top - insets.bottom)
        let s = super.sizeThatFits(inner)
        return CGSize(width: s.width + insets.left + insets.right, height: s.height + insets.top + insets.bottom)
    }
}

/// Row of basket contents; tap one to choose what you'll place next. Scrolls sideways when full.
final class BasketBar: UIView {
    var onSelect: ((String) -> Void)?
    private var buttons: [UIButton] = []
    private var keys: [String] = []
    private let countLabel = UILabel()
    private let bg = UIView()
    private let scroll = UIScrollView()
    var scale: CGFloat = 1
    var showCounts = true
    var colorblind: ColorblindMode = .off

    override init(frame: CGRect) {
        super.init(frame: frame)
        bg.backgroundColor = UIColor(white: 0, alpha: 0.45)
        bg.layer.cornerRadius = 16
        bg.isUserInteractionEnabled = false
        addSubview(bg)
        countLabel.textColor = .white
        countLabel.textAlignment = .center
        countLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .heavy)
        addSubview(countLabel)
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.delaysContentTouches = false
        addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(groups: [BasketGroup], selected: String?, used: Int, capacity: Int) {
        countLabel.text = "\(used)/\(capacity)"
        countLabel.textColor = used >= capacity ? UIColor(hex: StatusPalette.bad(colorblind)) : .white
        let newKeys = groups.map { $0.key }
        if newKeys != keys {
            buttons.forEach { $0.removeFromSuperview() }
            buttons = []
            keys = newKeys
            for g in groups {
                let b = UIButton(type: .custom)
                if let p = Catalog.product(g.product) { b.setImage(ProductIcons.icon(for: p, expired: g.expired), for: .normal) }
                b.imageView?.contentMode = .scaleAspectFill
                b.clipsToBounds = true
                b.layer.cornerRadius = 10
                b.backgroundColor = UIColor(hex: 0xEEF0F2)
                let key = g.key
                b.addAction(UIAction { [weak self] _ in self?.onSelect?(key) }, for: .touchUpInside)
                let badge = UILabel()
                badge.tag = 77
                badge.font = .systemFont(ofSize: 12, weight: .black)
                badge.textColor = .white
                badge.textAlignment = .center
                badge.backgroundColor = UIColor(white: 0, alpha: 0.72)
                badge.layer.cornerRadius = 8
                badge.layer.masksToBounds = true
                b.addSubview(badge)
                if g.expired {
                    let x = UIImageView(image: UIImage(systemName: "xmark.octagon.fill"))
                    x.tag = 78
                    x.tintColor = UIColor(hex: 0xE02424)
                    x.backgroundColor = .white
                    x.layer.cornerRadius = 9
                    x.clipsToBounds = true
                    b.addSubview(x)
                }
                scroll.addSubview(b)
                buttons.append(b)
            }
        }
        for (i, g) in groups.enumerated() where i < buttons.count {
            let b = buttons[i]
            let sel = g.key == selected
            b.layer.borderWidth = sel ? 3 : 1
            b.layer.borderColor = sel ? UIColor(hex: Theme.brand).cgColor : UIColor(white: 1, alpha: 0.35).cgColor
            if let badge = b.viewWithTag(77) as? UILabel {
                badge.text = "\(g.count)"
                badge.isHidden = !showCounts
            }
        }
        setNeedsLayout()
    }

    var preferredWidth: CGFloat {
        let s = 46 * scale
        return CGFloat(max(1, buttons.count)) * (s + 6) + 58 * scale
    }

    /// Keeps the selected item in view.
    func reveal(_ key: String?) {
        guard let key = key, let i = keys.firstIndex(of: key), i < buttons.count else { return }
        scroll.scrollRectToVisible(buttons[i].frame.insetBy(dx: -8, dy: 0), animated: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = 46 * scale
        bg.frame = bounds
        countLabel.frame = CGRect(x: 6, y: 0, width: 44 * scale, height: bounds.height)
        scroll.frame = CGRect(x: 52 * scale, y: 0, width: max(0, bounds.width - 52 * scale - 6), height: bounds.height)
        var x: CGFloat = 0
        for b in buttons {
            b.frame = CGRect(x: x, y: (bounds.height - s) / 2, width: s, height: s)
            if let badge = b.viewWithTag(77) {
                badge.frame = CGRect(x: s - 22, y: s - 18, width: 20, height: 16)
            }
            if let xmark = b.viewWithTag(78) {
                xmark.frame = CGRect(x: 2, y: 2, width: 18, height: 18)
            }
            x += s + 6
        }
        scroll.contentSize = CGSize(width: max(0, x - 6), height: bounds.height)
    }
}

/// Everything drawn over the 3D view. Touches that miss a button fall through to the controls layer.
final class HUDView: UIView {
    let timerLabel = UILabel()
    let levelLabel = UILabel()
    let remainingLabel = UILabel()
    let scoreLabel = UILabel()
    let comboLabel = PillLabel()
    let comboBar = UIView()
    private var floaters: [UILabel] = []
    private var nextFloater = 0
    let infoPanel = UIView()
    let progressTrack = UIView()
    let progressFill = UIView()
    let promptLabel = PillLabel()
    let toastLabel = PillLabel()
    let tipLabel = PillLabel()
    let fpsLabel = UILabel()
    let crosshair = CrosshairView()
    let basketBar = BasketBar()
    let pauseButton = RoundButton(symbol: "pause.fill")
    let interactButton = RoundButton(symbol: "hand.tap.fill")
    let dropButton = RoundButton(symbol: "arrow.down.to.line")
    private(set) var skillButtons: [SkillID: RoundButton] = [:]

    private var settings = DisplaySettings()
    private var progressValue: CGFloat = 0
    private var comboValue: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        // HUD opacity is applied per element; group opacity on a full-screen layer forces an
        // expensive offscreen render every frame.
        layer.allowsGroupOpacity = false

        infoPanel.layer.cornerRadius = 14
        infoPanel.isUserInteractionEnabled = false
        addSubview(infoPanel)
        for l in [timerLabel, levelLabel, remainingLabel, scoreLabel] {
            l.textColor = .white
            infoPanel.addSubview(l)
        }
        scoreLabel.textColor = UIColor(hex: 0xFFD54A)
        comboLabel.textColor = .white
        comboLabel.textAlignment = .center
        comboLabel.isHidden = true
        comboLabel.insets = UIEdgeInsets(top: 4, left: 12, bottom: 7, right: 12)
        addSubview(comboLabel)
        comboBar.backgroundColor = UIColor(white: 1, alpha: 0.9)
        comboBar.layer.cornerRadius = 1.5
        comboLabel.addSubview(comboBar)
        for _ in 0..<4 {
            let f = UILabel()
            f.textAlignment = .center
            f.alpha = 0
            f.isUserInteractionEnabled = false
            f.shadowColor = UIColor(white: 0, alpha: 0.8)
            f.shadowOffset = CGSize(width: 0, height: 1)
            addSubview(f)
            floaters.append(f)
        }
        progressTrack.backgroundColor = UIColor(white: 1, alpha: 0.18)
        progressTrack.layer.cornerRadius = 4
        progressTrack.isUserInteractionEnabled = false
        progressFill.layer.cornerRadius = 4
        progressTrack.addSubview(progressFill)
        addSubview(progressTrack)
        for p in [promptLabel, toastLabel, tipLabel] {
            p.textColor = .white
            p.textAlignment = .center
            p.layer.masksToBounds = false   // rounded background without an offscreen mask pass
            p.numberOfLines = 1
            addSubview(p)
        }
        tipLabel.numberOfLines = 3
        tipLabel.insets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        toastLabel.alpha = 0
        toastLabel.numberOfLines = 2
        fpsLabel.textColor = .yellow
        fpsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        addSubview(fpsLabel)
        addSubview(crosshair)
        addSubview(basketBar)

        addSubview(pauseButton)
        addSubview(interactButton)
        addSubview(dropButton)
        interactButton.caption.text = "Use"
        dropButton.caption.text = "Drop"
        for s in SkillID.allCases {
            let b = RoundButton(symbol: s.symbol)
            b.caption.text = s.shortName
            b.countdown.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
            skillButtons[s] = b
            addSubview(b)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let v = super.hitTest(point, with: event)
        return v === self || v === basketBar ? nil : v
    }

    func apply(_ d: DisplaySettings) {
        settings = d
        alpha = CGFloat(d.hudOpacity)
        let ts = CGFloat(d.textScale)
        let bg = UIColor(white: 0, alpha: d.highContrastHUD ? 0.85 : 0.45)
        infoPanel.backgroundColor = bg
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 24 * ts, weight: .heavy)
        levelLabel.font = .systemFont(ofSize: 11 * ts, weight: .semibold)
        remainingLabel.font = .systemFont(ofSize: 13 * ts, weight: .bold)
        scoreLabel.font = .monospacedDigitSystemFont(ofSize: 13 * ts, weight: .heavy)
        scoreLabel.isHidden = !d.showScore
        comboLabel.font = .systemFont(ofSize: 15 * ts, weight: .black)
        comboLabel.backgroundColor = UIColor(hex: Theme.brand, alpha: 0.92)
        for f in floaters { f.font = .systemFont(ofSize: 17 * ts, weight: .black) }
        levelLabel.textColor = UIColor(white: 1, alpha: 0.75)
        promptLabel.font = .systemFont(ofSize: 14 * ts, weight: .semibold)
        toastLabel.font = .systemFont(ofSize: 14 * ts, weight: .semibold)
        tipLabel.font = .systemFont(ofSize: 13 * ts, weight: .semibold)
        for p in [promptLabel, toastLabel] { p.backgroundColor = bg }
        tipLabel.backgroundColor = UIColor(hex: 0x1F618D, alpha: d.highContrastHUD ? 0.95 : 0.85)
        progressFill.backgroundColor = UIColor(hex: StatusPalette.good(d.colorblind))
        progressTrack.isHidden = !d.showProgressBar
        crosshair.style = d.crosshair
        crosshair.color = UIColor(hex: d.crosshairColor.hex)
        crosshair.isHidden = d.crosshair == .none
        timerLabel.isHidden = !d.showTimer
        remainingLabel.isHidden = !d.showRemaining
        fpsLabel.isHidden = !(d.showFPS || d.perfStats)
        basketBar.scale = CGFloat(d.basketBarScale) * CGFloat(d.hudScale)
        basketBar.showCounts = d.basketCounts
        basketBar.colorblind = d.colorblind
        basketBar.subviews.first?.backgroundColor = bg
        for b in skillButtons.values { b.caption.isHidden = !d.showSkillLabels }
        interactButton.caption.isHidden = !d.showSkillLabels
        dropButton.caption.isHidden = !d.showSkillLabels
        for b in [interactButton, dropButton, pauseButton] + Array(skillButtons.values) {
            b.caption.font = .systemFont(ofSize: 10 * ts, weight: .bold)
            b.backgroundColor = UIColor(white: 0.08, alpha: d.highContrastHUD ? 0.85 : 0.55)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let d = settings
        let hs = CGFloat(d.hudScale)
        let bs = CGFloat(d.buttonSize) * hs
        let inset = safeAreaInsets
        let left = inset.left + 14, right = bounds.width - inset.right - 14
        let top = max(inset.top, 8) + 6

        // Info panel (timer, level, remaining) — top-left, or top-right when left-handed
        timerLabel.sizeToFit(); levelLabel.sizeToFit(); remainingLabel.sizeToFit(); scoreLabel.sizeToFit()
        let panelW = max(timerLabel.bounds.width, levelLabel.bounds.width, remainingLabel.bounds.width, scoreLabel.bounds.width) + 24
        var h: CGFloat = 8 + levelLabel.bounds.height
        if !timerLabel.isHidden { h += timerLabel.bounds.height }
        if !remainingLabel.isHidden { h += remainingLabel.bounds.height }
        if !scoreLabel.isHidden { h += scoreLabel.bounds.height + 1 }
        h += 8
        infoPanel.frame = CGRect(x: d.leftHanded ? right - panelW - 50 * hs : left, y: top, width: panelW, height: h)
        var y: CGFloat = 6
        levelLabel.frame.origin = CGPoint(x: 12, y: y); y += levelLabel.bounds.height
        if !timerLabel.isHidden { timerLabel.frame.origin = CGPoint(x: 12, y: y); y += timerLabel.bounds.height }
        if !remainingLabel.isHidden { remainingLabel.frame.origin = CGPoint(x: 12, y: y); y += remainingLabel.bounds.height + 1 }
        scoreLabel.frame.origin = CGPoint(x: 12, y: y)
        fpsLabel.sizeToFit()
        fpsLabel.frame.origin = CGPoint(x: infoPanel.frame.minX + 4, y: infoPanel.frame.maxY + 4)

        let ps = 40 * hs
        pauseButton.frame = CGRect(x: d.leftHanded ? left : right - ps, y: top, width: ps, height: ps)

        // Progress bar at top center
        let pw = min(bounds.width * 0.32, 300)
        progressTrack.frame = CGRect(x: bounds.midX - pw / 2, y: top + 6, width: pw, height: 8)
        progressFill.frame = CGRect(x: 0, y: 0, width: max(8, pw * progressValue), height: 8)

        // Combo pill beside the progress bar
        let comboSize = comboLabel.sizeThatFits(CGSize(width: 240, height: 60))
        let comboX = d.leftHanded ? progressTrack.frame.minX - comboSize.width - 14 : progressTrack.frame.maxX + 14
        comboLabel.frame = CGRect(x: comboX, y: top - 3, width: comboSize.width, height: comboSize.height)
        comboLabel.layer.cornerRadius = comboSize.height / 2
        comboBar.frame = CGRect(x: 12, y: comboSize.height - 6, width: (comboSize.width - 24) * comboValue, height: 3)

        // Tip + toast under the progress bar
        let maxW = min(bounds.width * 0.5, 460)
        let tipSize = tipLabel.sizeThatFits(CGSize(width: maxW, height: 200))
        tipLabel.frame = CGRect(x: bounds.midX - min(maxW, tipSize.width) / 2, y: progressTrack.frame.maxY + 10,
                                width: min(maxW, tipSize.width), height: tipSize.height)
        tipLabel.layer.cornerRadius = 12
        let toastTop = tipLabel.isHidden ? progressTrack.frame.maxY + 10 : tipLabel.frame.maxY + 6
        let toastSize = toastLabel.sizeThatFits(CGSize(width: maxW, height: 100))
        toastLabel.frame = CGRect(x: bounds.midX - min(maxW, toastSize.width) / 2, y: toastTop,
                                  width: min(maxW, toastSize.width), height: toastSize.height)
        toastLabel.layer.cornerRadius = min(14, toastSize.height / 2)

        // Crosshair + prompt
        let cs = 22 * CGFloat(d.crosshairSize) * hs
        crosshair.frame = CGRect(x: bounds.midX - cs / 2, y: bounds.midY - cs / 2, width: cs, height: cs)
        let promptSize = promptLabel.sizeThatFits(CGSize(width: bounds.width * 0.6, height: 60))
        promptLabel.frame = CGRect(x: bounds.midX - promptSize.width / 2, y: bounds.midY + cs / 2 + 14,
                                   width: promptSize.width, height: promptSize.height)
        promptLabel.layer.cornerRadius = promptSize.height / 2


        // Action cluster
        let big = 78 * bs, mid = 52 * bs, small = 48 * bs
        let bottom = bounds.height - max(inset.bottom, 10) - 24 * hs
        let anchorX = d.leftHanded ? left + 10 * hs : right - 10 * hs - big
        interactButton.frame = CGRect(x: anchorX, y: bottom - big, width: big, height: big)
        let dropX = d.leftHanded ? interactButton.frame.maxX + 16 * hs : interactButton.frame.minX - 16 * hs - mid
        dropButton.frame = CGRect(x: dropX, y: bottom - mid, width: mid, height: mid)
        let center = CGPoint(x: interactButton.frame.midX, y: interactButton.frame.midY)
        let radius = big / 2 + small / 2 + 78 * bs
        let angles: [CGFloat] = [-90, -112, -134, -156, -178].map { $0 * .pi / 180 }
        for (i, s) in SkillID.allCases.enumerated() {
            guard let b = skillButtons[s] else { continue }
            let a = angles[i]
            let x = center.x + cos(a) * radius * (d.leftHanded ? -1 : 1)
            let yy = center.y + sin(a) * radius
            b.frame = CGRect(x: x - small / 2, y: yy - small / 2, width: small, height: small)
        }

        // Basket bar: fits between the move-stick zone and the action buttons (scrolls if needed).
        let bh = 58 * basketBar.scale
        let stickZone = 190 * hs
        var clusterEdge = d.leftHanded ? interactButton.frame.maxX : interactButton.frame.minX
        for b in [dropButton] + Array(skillButtons.values) where b.frame.maxY > bounds.height - bh - 30 {
            clusterEdge = d.leftHanded ? max(clusterEdge, b.frame.maxX) : min(clusterEdge, b.frame.minX)
        }
        let lo = d.leftHanded ? clusterEdge + 12 : left + stickZone
        let hi = d.leftHanded ? right - stickZone : clusterEdge - 12
        let avail = max(120, hi - lo)
        let bw = min(basketBar.preferredWidth, avail)
        basketBar.frame = CGRect(x: lo + (avail - bw) / 2, y: bounds.height - max(inset.bottom, 8) - bh - 6, width: bw, height: bh)
    }

    // MARK: Updates

    func setPrompt(_ text: String?) {
        let show = settings.showPrompts && text != nil
        if promptLabel.text != text { promptLabel.text = text; setNeedsLayout() }
        promptLabel.isHidden = !show
    }

    func setTip(_ text: String?) {
        if tipLabel.text != text { tipLabel.text = text; setNeedsLayout() }
        tipLabel.isHidden = text == nil
    }

    func showToast(_ text: String, style: ToastStyle) {
        guard settings.showToasts else { return }
        let cb = settings.colorblind
        let color: UIColor
        switch style {
        case .info: color = UIColor(white: 0, alpha: settings.highContrastHUD ? 0.85 : 0.55)
        case .good: color = UIColor(hex: StatusPalette.good(cb), alpha: 0.88)
        case .warn: color = UIColor(hex: 0xB9770E, alpha: 0.92)
        case .bad: color = UIColor(hex: StatusPalette.bad(cb), alpha: 0.9)
        }
        toastLabel.text = text
        toastLabel.backgroundColor = color
        setNeedsLayout()
        layoutIfNeeded()
        toastLabel.layer.removeAllAnimations()
        toastLabel.alpha = 1
        UIView.animate(withDuration: 0.4, delay: 2.8, options: [.allowUserInteraction], animations: {
            self.toastLabel.alpha = 0
        })
    }

    func setStatus(level: String, time: String, frozen: Bool, remaining: Int, progress: Double) {
        if levelLabel.text != level { levelLabel.text = level; setNeedsLayout() }
        if timerLabel.text != time { timerLabel.text = time; setNeedsLayout() }
        timerLabel.textColor = frozen ? UIColor(hex: 0x7FDBFF) : .white
        let rem = remaining == 1 ? "1 item left" : "\(remaining) items left"
        if remainingLabel.text != rem { remainingLabel.text = rem; setNeedsLayout() }
        let p = CGFloat(max(0, min(1, progress)))
        if abs(p - progressValue) > 0.001 {
            progressValue = p
            let pw = progressTrack.bounds.width
            progressFill.frame = CGRect(x: 0, y: 0, width: max(8, pw * p), height: 8)
        }
    }

    /// Score line and the combo pill (hidden below x2).
    func setScore(_ score: Int, streak: Int, multiplier: Int, comboLeft: Double) {
        let text = "\(score.formatted()) pts"
        if scoreLabel.text != text { scoreLabel.text = text; setNeedsLayout() }
        let show = settings.showScore && streak >= 2
        if comboLabel.isHidden == show { comboLabel.isHidden = !show; setNeedsLayout() }
        guard show else { return }
        let label = multiplier > 1 ? "x\(multiplier)  ·  \(streak) in a row" : "\(streak) in a row"
        if comboLabel.text != label { comboLabel.text = label; setNeedsLayout() }
        comboValue = CGFloat(max(0, min(1, comboLeft)))
        comboBar.frame.size.width = max(0, (comboLabel.bounds.width - 24) * comboValue)
    }

    /// A little "+30" that floats up from the crosshair.
    func floatPoints(_ points: Int, multiplier: Int) {
        guard settings.showScore, !floaters.isEmpty else { return }
        let f = floaters[nextFloater % floaters.count]
        nextFloater += 1
        f.text = "+\(points)"
        f.textColor = multiplier >= 3 ? UIColor(hex: 0xFFD54A) : .white
        f.sizeToFit()
        let jitter = CGFloat((nextFloater * 37) % 50) - 25
        f.center = CGPoint(x: bounds.midX + 34 + jitter, y: bounds.midY - 18)
        f.layer.removeAllAnimations()
        f.alpha = 1
        f.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        UIView.animate(withDuration: 0.7, delay: 0, options: [.curveEaseOut, .allowUserInteraction], animations: {
            f.center.y -= 46
            f.alpha = 0
            f.transform = .identity
        })
    }
}
