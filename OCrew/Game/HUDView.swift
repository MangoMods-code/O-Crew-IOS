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

/// Everything drawn over the 3D view. Touches that miss a button fall through to the controls layer.
final class HUDView: UIView {
    let moneyLabel = UILabel()
    let dayLabel = UILabel()
    let ratingLabel = UILabel()
    let infoPanel = UIView()
    let clockLabel = PillLabel()
    let phaseLabel = PillLabel()
    let promptLabel = PillLabel()
    let toastLabel = PillLabel()
    let tipLabel = PillLabel()
    let fpsLabel = UILabel()
    let crosshair = CrosshairView()
    let pauseButton = RoundButton(symbol: "pause.fill")
    let interactButton = RoundButton(symbol: "hand.tap.fill")
    let dropButton = RoundButton(symbol: "arrow.down.to.line")
    private(set) var skillButtons: [SkillID: RoundButton] = [:]

    private var settings = DisplaySettings()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        infoPanel.layer.cornerRadius = 14
        infoPanel.isUserInteractionEnabled = false
        addSubview(infoPanel)
        for l in [moneyLabel, dayLabel, ratingLabel] {
            l.textColor = .white
            infoPanel.addSubview(l)
        }
        for p in [clockLabel, phaseLabel, promptLabel, toastLabel, tipLabel] {
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
        return v === self ? nil : v
    }

    func apply(_ d: DisplaySettings) {
        settings = d
        alpha = CGFloat(d.hudOpacity)
        let ts = CGFloat(d.textScale)
        let bg = UIColor(white: 0, alpha: d.highContrastHUD ? 0.85 : 0.45)
        infoPanel.backgroundColor = bg
        moneyLabel.font = .monospacedDigitSystemFont(ofSize: 22 * ts, weight: .heavy)
        dayLabel.font = .systemFont(ofSize: 12 * ts, weight: .semibold)
        ratingLabel.font = .systemFont(ofSize: 12 * ts, weight: .semibold)
        clockLabel.font = .monospacedDigitSystemFont(ofSize: 15 * ts, weight: .bold)
        phaseLabel.font = .systemFont(ofSize: 11 * ts, weight: .heavy)
        promptLabel.font = .systemFont(ofSize: 14 * ts, weight: .semibold)
        toastLabel.font = .systemFont(ofSize: 14 * ts, weight: .semibold)
        tipLabel.font = .systemFont(ofSize: 13 * ts, weight: .semibold)
        for p in [clockLabel, promptLabel, toastLabel] { p.backgroundColor = bg }
        tipLabel.backgroundColor = UIColor(hex: 0x1F618D, alpha: d.highContrastHUD ? 0.95 : 0.8)
        crosshair.style = d.crosshair
        crosshair.color = UIColor(hex: d.crosshairColor.hex)
        crosshair.isHidden = d.crosshair == .none
        moneyLabel.isHidden = !d.showMoney
        ratingLabel.isHidden = !d.showRating
        clockLabel.isHidden = !d.showClock
        fpsLabel.isHidden = !d.showFPS
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

        // Info panel
        moneyLabel.sizeToFit(); dayLabel.sizeToFit(); ratingLabel.sizeToFit()
        let panelW = max(moneyLabel.bounds.width, dayLabel.bounds.width, ratingLabel.bounds.width) + 24
        let panelH = moneyLabel.bounds.height + dayLabel.bounds.height + (ratingLabel.isHidden ? 0 : ratingLabel.bounds.height) + 16
        infoPanel.frame = CGRect(x: d.leftHanded ? right - panelW - 50 * hs : left, y: top, width: panelW, height: panelH)
        moneyLabel.frame.origin = CGPoint(x: 12, y: 6)
        dayLabel.frame.origin = CGPoint(x: 12, y: moneyLabel.frame.maxY + 1)
        ratingLabel.frame.origin = CGPoint(x: 12, y: dayLabel.frame.maxY + 1)
        fpsLabel.sizeToFit()
        fpsLabel.frame.origin = CGPoint(x: infoPanel.frame.minX + 4, y: infoPanel.frame.maxY + 4)

        // Pause (opposite corner of panel)
        let ps = 40 * hs
        pauseButton.frame = CGRect(x: d.leftHanded ? left : right - ps, y: top, width: ps, height: ps)

        // Clock + phase
        clockLabel.sizeToFit(); phaseLabel.sizeToFit()
        let cw = clockLabel.bounds.width + phaseLabel.bounds.width + 6
        clockLabel.frame = CGRect(x: bounds.midX - cw / 2, y: top, width: clockLabel.bounds.width, height: clockLabel.bounds.height)
        phaseLabel.frame = CGRect(x: clockLabel.frame.maxX + 6, y: top + (clockLabel.bounds.height - phaseLabel.bounds.height) / 2,
                                  width: phaseLabel.bounds.width, height: phaseLabel.bounds.height)
        clockLabel.layer.cornerRadius = clockLabel.bounds.height / 2
        phaseLabel.layer.cornerRadius = phaseLabel.bounds.height / 2

        // Tip + toast under the clock
        let maxW = min(bounds.width * 0.5, 460)
        let tipSize = tipLabel.sizeThatFits(CGSize(width: maxW, height: 200))
        tipLabel.frame = CGRect(x: bounds.midX - min(maxW, tipSize.width) / 2, y: clockLabel.frame.maxY + 8,
                                width: min(maxW, tipSize.width), height: tipSize.height)
        tipLabel.layer.cornerRadius = 12
        let toastTop = tipLabel.isHidden ? clockLabel.frame.maxY + 8 : tipLabel.frame.maxY + 6
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

        // Skills arc above/beside the main button
        let center = CGPoint(x: interactButton.frame.midX, y: interactButton.frame.midY)
        let radius = big / 2 + small / 2 + 78 * bs
        let angles: [CGFloat] = [-90, -112, -134, -156, -178].map { $0 * .pi / 180 }
        for (i, s) in SkillID.allCases.enumerated() {
            guard let b = skillButtons[s] else { continue }
            let a = angles[i]
            let x = center.x + cos(a) * radius * (d.leftHanded ? -1 : 1)
            let y = center.y + sin(a) * radius
            b.frame = CGRect(x: x - small / 2, y: y - small / 2, width: small, height: small)
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

    func setStatus(money: String, day: String, rating: Double, clock: String, phase: Phase) {
        if moneyLabel.text != money { moneyLabel.text = money; setNeedsLayout() }
        if dayLabel.text != day { dayLabel.text = day; setNeedsLayout() }
        let stars = String(format: "★ %.1f", rating)
        if ratingLabel.text != stars { ratingLabel.text = stars; setNeedsLayout() }
        ratingLabel.textColor = UIColor(hex: StatusPalette.forLevel(rating / 5, settings.colorblind))
        if clockLabel.text != clock { clockLabel.text = clock; setNeedsLayout() }
        let pair: (String, UInt32)
        switch phase {
        case .prep: pair = ("PREP", 0x5D6D7E)
        case .open: pair = ("OPEN", StatusPalette.good(settings.colorblind))
        case .closing: pair = ("CLOSING", 0xB9770E)
        case .ended: pair = ("CLOSED", StatusPalette.bad(settings.colorblind))
        }
        let (text, color) = pair
        if phaseLabel.text != text {
            phaseLabel.text = text
            phaseLabel.backgroundColor = UIColor(hex: color, alpha: 0.9)
            setNeedsLayout()
        }
    }
}
