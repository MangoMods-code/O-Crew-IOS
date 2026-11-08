import UIKit
import simd

/// Full-screen touch layer: virtual move stick on one half, look-drag (and tap-to-interact) on the other.
final class ControlsView: UIView {
    private(set) var moveVector: SIMD2<Float> = .zero
    private var lookAccum = CGPoint.zero
    var onTap: ((CGPoint) -> Void)?

    private var moveTouch: UITouch?
    private var moveOrigin = CGPoint.zero
    private var lookTouch: UITouch?
    private var lookLast = CGPoint.zero
    private var lookStart = CGPoint.zero
    private var lookStartTime: TimeInterval = 0
    private var lookMoved: CGFloat = 0

    private let base = UIView()
    private let knob = UIView()

    var leftHanded = false
    var floating = true
    var radius: CGFloat = 62
    var tapEnabled = true
    var opacity: CGFloat = 0.9

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        base.isUserInteractionEnabled = false
        knob.isUserInteractionEnabled = false
        base.backgroundColor = UIColor(white: 1, alpha: 0.12)
        base.layer.borderColor = UIColor(white: 1, alpha: 0.45).cgColor
        base.layer.borderWidth = 2
        knob.backgroundColor = UIColor(white: 1, alpha: 0.75)
        knob.layer.shadowColor = UIColor.black.cgColor
        knob.layer.shadowOpacity = 0.35
        knob.layer.shadowRadius = 6
        knob.layer.shouldRasterize = true
        knob.layer.rasterizationScale = UIScreen.main.scale
        addSubview(base)
        addSubview(knob)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ d: DisplaySettings) {
        leftHanded = d.leftHanded
        floating = d.joystickMode == .floating
        radius = 62 * CGFloat(d.joystickSize) * CGFloat(d.hudScale)
        tapEnabled = d.tapToInteract
        opacity = CGFloat(d.hudOpacity)
        layoutStick()
    }

    /// Returns look movement since the last call.
    func consumeLook() -> CGPoint {
        let d = lookAccum
        lookAccum = .zero
        return d
    }

    private var fixedCenter: CGPoint {
        let inset = safeAreaInsets
        let x = leftHanded ? bounds.width - inset.right - radius - 44 : inset.left + radius + 44
        return CGPoint(x: x, y: bounds.height - inset.bottom - radius - 34)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutStick()
    }

    private func layoutStick() {
        base.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        base.layer.cornerRadius = radius
        knob.bounds = CGRect(x: 0, y: 0, width: radius * 0.9, height: radius * 0.9)
        knob.layer.cornerRadius = radius * 0.45
        knob.layer.shadowPath = UIBezierPath(ovalIn: knob.bounds).cgPath
        if moveTouch == nil {
            base.center = fixedCenter
            knob.center = fixedCenter
            let idle: CGFloat = floating ? 0.35 : 1
            base.alpha = opacity * idle
            knob.alpha = opacity * idle
        }
    }

    private func isMoveSide(_ p: CGPoint) -> Bool {
        leftHanded ? p.x > bounds.width * 0.5 : p.x < bounds.width * 0.5
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            if moveTouch == nil && isMoveSide(p) {
                if !floating && hypot(p.x - fixedCenter.x, p.y - fixedCenter.y) > radius * 2.2 {
                    // Too far from a fixed stick: treat as look.
                    beginLook(t, p)
                    continue
                }
                moveTouch = t
                moveOrigin = floating ? p : fixedCenter
                base.center = moveOrigin
                knob.center = moveOrigin
                base.alpha = opacity
                knob.alpha = opacity
                updateMove(p)
            } else if lookTouch == nil {
                beginLook(t, p)
            }
        }
    }

    private func beginLook(_ t: UITouch, _ p: CGPoint) {
        guard lookTouch == nil else { return }
        lookTouch = t
        lookLast = p
        lookStart = p
        lookStartTime = t.timestamp
        lookMoved = 0
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            if t === moveTouch {
                updateMove(p)
            } else if t === lookTouch {
                lookAccum.x += p.x - lookLast.x
                lookAccum.y += p.y - lookLast.y
                lookMoved = max(lookMoved, hypot(p.x - lookStart.x, p.y - lookStart.y))
                lookLast = p
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if t === moveTouch {
                endMove()
            } else if t === lookTouch {
                let p = t.location(in: self)
                if tapEnabled && t.timestamp - lookStartTime < 0.28 && lookMoved < 14 {
                    onTap?(p)
                }
                lookTouch = nil
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if t === moveTouch { endMove() }
            if t === lookTouch { lookTouch = nil }
        }
    }

    private func updateMove(_ p: CGPoint) {
        var dx = p.x - moveOrigin.x
        var dy = p.y - moveOrigin.y
        let d = hypot(dx, dy)
        if d > radius { dx *= radius / d; dy *= radius / d }
        knob.center = CGPoint(x: moveOrigin.x + dx, y: moveOrigin.y + dy)
        var v = SIMD2<Float>(Float(dx / radius), Float(-dy / radius))
        let mag = simd_length(v)
        // Small dead zone, then rescale so movement starts smoothly.
        if mag < 0.12 { v = .zero } else { v = v / mag * min(1, (mag - 0.12) / 0.88) }
        moveVector = v
    }

    private func endMove() {
        moveTouch = nil
        moveVector = .zero
        UIView.animate(withDuration: 0.15) { self.layoutStick() }
    }

    func reset() {
        moveTouch = nil
        lookTouch = nil
        moveVector = .zero
        lookAccum = .zero
        layoutStick()
    }
}
