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
        caption.layer.shadowColor = UIColor.black.cgColor
        caption.layer.shadowOpacity = 0.8
        caption.layer.shadowRadius = 2
        caption.layer.shadowOffset = .zero
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

/// Row of basket contents; tap one to choose what you'll place next.
final class BasketBar: UIView {
    var onSelect: ((String) -> Void)?
    private var buttons: [UIButton] = []
    private var keys: [String] = []
    private let countLabel = UILabel()
    private let bg = UIView()
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
                if let p = Catalog.product(g.product) { b.setImage(Models.labelImage(for: p), for: .normal) }
                b.imageView?.contentMode = .scaleAspectFill
                b.clipsToBounds = true
                b.layer.cornerRadius = 10
                let key = g.key
                b.addAction(UIAction { [weak self] _ in self?.onSelect?(key) }, for: .touchUpInside)
                let badge = UILabel()
                badge.tag = 77
                badge.font = .systemFont(ofSize: 12, weight: .black)
                badge.textColor = .white
                badge.textAlignment = .center
                badge.backgroundColor = UIColor(white: 0, alpha: 0.7)
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
                addSubview(b)
                buttons.append(b)
            }
        }
        for (i, g) in groups.enumerated() where i < buttons.count {
            let b = buttons[i]
            let sel = g.key == selected
            b.layer.borderWidth = sel ? 3 : 1
            b.layer.borderColor = sel ? UIColor(hex: Theme.brand).cgColor : UIColor(white: 1, alpha: 0.35).cgColor
            b.alpha = sel ? 1 : 0.8
            if let badge = b.viewWithTag(77) as? UILabel {
                badge.text = "\(g.count)"
                badge.isHidden = !showCounts
            }
        }
        setNeedsLayout()
    }

    var preferredWidth: CGFloat {
        let s = 46 * scale
        return CGFloat(max(1, buttons.count)) * (s + 6) + 56 * scale
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = 46 * scale
        bg.frame = bounds
        countLabel.frame = CGRect(x: 6, y: 0, width: 44 * scale, height: bounds.height)
        var x = 52 * scale
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
    }
}

/// Everything drawn over the 3D view. Touches that miss a button fall through to the controls layer.
final class HUDView: UIView {
    let timerLabel = UILabel()
    let levelLabel = UILabel()
    let remainingLabel = UILabel()
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        infoPanel.layer.cornerRadius = 14
        infoPanel.isUserInteractionEnabled = false
        addSubview(infoPanel)
        for l in [timerLabel, levelLabel, remainingLabel] {
            l.textColor = .white
            infoPanel.addSubview(l)
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
            p.layer.masksToBounds = true
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
        fpsLabel.isHidden = !d.showFPS
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
        timerLabel.sizeToFit(); levelLabel.sizeToFit(); remainingLabel.sizeToFit()
        let panelW = max(timerLabel.bounds.width, levelLabel.bounds.width, remainingLabel.bounds.width) + 24
        var h: CGFloat = 8 + levelLabel.bounds.height
        if !timerLabel.isHidden { h += timerLabel.bounds.height }
        if !remainingLabel.isHidden { h += remainingLabel.bounds.height }
        h += 8
        infoPanel.frame = CGRect(x: d.leftHanded ? right - panelW - 50 * hs : left, y: top, width: panelW, height: h)
        var y: CGFloat = 6
        levelLabel.frame.origin = CGPoint(x: 12, y: y); y += levelLabel.bounds.height
        if !timerLabel.isHidden { timerLabel.frame.origin = CGPoint(x: 12, y: y); y += timerLabel.bounds.height }
        remainingLabel.frame.origin = CGPoint(x: 12, y: y)
        fpsLabel.sizeToFit()
        fpsLabel.frame.origin = CGPoint(x: infoPanel.frame.minX + 4, y: infoPanel.frame.maxY + 4)

        let ps = 40 * hs
        pauseButton.frame = CGRect(x: d.leftHanded ? left : right - ps, y: top, width: ps, height: ps)

        // Progress bar at top center
        let pw = min(bounds.width * 0.32, 300)
        progressTrack.frame = CGRect(x: bounds.midX - pw / 2, y: top + 6, width: pw, height: 8)
        progressFill.frame = CGRect(x: 0, y: 0, width: max(8, pw * progressValue), height: 8)

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

        // Basket bar bottom center
        let bh = 58 * basketBar.scale
        let bw = min(basketBar.preferredWidth, bounds.width * 0.5)
        basketBar.frame = CGRect(x: bounds.midX - bw / 2, y: bounds.height - max(inset.bottom, 8) - bh - 6, width: bw, height: bh)

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
}
