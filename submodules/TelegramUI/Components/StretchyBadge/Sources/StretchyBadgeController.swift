import UIKit

public final class StretchyBadgeController: NSObject, UIGestureRecognizerDelegate {
    public let badgeView: UIView
    public private(set) weak var container: UIView?
    public var resolveContainer: (() -> UIView?)?
    public var color: UIColor
    public var snapDistance: CGFloat = 84
    public var popDistance: CGFloat = 50
    public var onPop: (() -> Void)?
    public var onDragChanged: ((Bool) -> Void)?

    public let panGesture: UIPanGestureRecognizer

    private var origin = CGPoint.zero
    private var radius: CGFloat = 10
    private var floating: UIView?
    private let shape = CAShapeLayer()
    private var detached = false
    private var neckRetract: CGFloat = 0
    private var link: CADisplayLink?
    private var settleBlock: (() -> Void)?
    private let snapFeedback = UIImpactFeedbackGenerator(style: .light)
    private let popFeedback = UIImpactFeedbackGenerator(style: .medium)

    public init(badgeView: UIView, container: UIView, color: UIColor, installsGesture: Bool = true) {
        self.badgeView = badgeView
        self.container = container
        self.color = color
        panGesture = UIPanGestureRecognizer()
        super.init()
        panGesture.addTarget(self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        if installsGesture {
            badgeView.isUserInteractionEnabled = true
            badgeView.addGestureRecognizer(panGesture)
        }
    }

    deinit {
        link?.invalidate()
    }

    // MARK: - Programmatic drag

    public var badgeCenter: CGPoint {
        guard let container else { return .zero }
        return badgeView.convert(CGPoint(x: badgeView.bounds.midX, y: badgeView.bounds.midY), to: container)
    }

    public func beginDrag() {
        guard let container else { return }
        begin(in: container)
    }

    public func updateDrag(to point: CGPoint) {
        move(to: point)
    }

    public func endDrag(at point: CGPoint) {
        end(at: point)
    }

    // MARK: - Gesture

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began, let resolved = resolveContainer?() {
            container = resolved
        }
        guard let container else { return }
        switch gesture.state {
        case .began:
            begin(in: container)
        case .changed:
            let t = gesture.translation(in: container)
            move(to: CGPoint(x: origin.x + t.x, y: origin.y + t.y))
        case .ended, .cancelled, .failed:
            let t = gesture.translation(in: container)
            end(at: CGPoint(x: origin.x + t.x, y: origin.y + t.y))
        default:
            break
        }
    }

    private func begin(in container: UIView) {
        stopLink()
        settleBlock = nil
        floating?.removeFromSuperview()
        origin = badgeView.convert(CGPoint(x: badgeView.bounds.midX, y: badgeView.bounds.midY), to: container)
        radius = min(badgeView.bounds.height, badgeView.bounds.width) / 2
        detached = false
        neckRetract = 0

        let copy = badgeView.snapshotView(afterScreenUpdates: false) ?? UIView()
        copy.frame = badgeView.convert(badgeView.bounds, to: container)
        container.addSubview(copy)
        floating = copy

        shape.fillColor = color.cgColor
        shape.path = nil
        container.layer.insertSublayer(shape, below: copy.layer)
        badgeView.alpha = 0
        snapFeedback.prepare()
        popFeedback.prepare()
        onDragChanged?(true)
    }

    private func move(to point: CGPoint) {
        guard let floating else { return }
        let dx = point.x - origin.x, dy = point.y - origin.y
        let distance = hypot(dx, dy)
        if !detached && distance > snapDistance {
            detach()
        }
        floating.center = point
        if detached {
            floating.transform = .identity
        } else {
            let k = min(distance / snapDistance, 1)
            floating.transform = Self.stretch(angle: atan2(dy, dx), along: 1 + 0.14 * k, across: 1 - 0.08 * k)
        }
        updateShape(head: point)
    }

    private func end(at point: CGPoint) {
        guard let floating else { return }
        onDragChanged?(false)
        let distance = hypot(point.x - origin.x, point.y - origin.y)
        if detached && distance > popDistance {
            floating.removeFromSuperview()
            self.floating = nil
            shape.removeFromSuperlayer()
            stopLink()
            if let container {
                popFeedback.impactOccurred()
                Self.pop(at: point, in: container, color: color, radius: radius)
            }
            onPop?()
            return
        }
        let wasDetached = detached
        UIView.animate(withDuration: wasDetached ? 0.45 : 0.6, delay: 0, usingSpringWithDamping: wasDetached ? 0.62 : 0.38,
                       initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            floating.center = self.origin
            floating.transform = .identity
        }
        if wasDetached {
            shape.path = nil
        }
        startLink { [weak self] in
            guard let self, let floating = self.floating else { return }
            let head = floating.layer.presentation()?.position ?? floating.center
            if !wasDetached {
                self.updateShape(head: head)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (wasDetached ? 0.45 : 0.6)) { [weak self] in
            guard let self, self.floating === floating else { return }
            self.finishReturn()
        }
    }

    private func finishReturn() {
        stopLink()
        floating?.removeFromSuperview()
        floating = nil
        shape.removeFromSuperlayer()
        badgeView.alpha = 1
        if detached {
            badgeView.transform = CGAffineTransform(scaleX: 1.25, y: 0.85)
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.35, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
                self.badgeView.transform = .identity
            }
        }
        detached = false
    }

    private func detach() {
        detached = true
        snapFeedback.impactOccurred()
        let started = CACurrentMediaTime()
        startLink { [weak self] in
            guard let self, let floating = self.floating else { return }
            let t = min((CACurrentMediaTime() - started) / 0.16, 1)
            self.neckRetract = CGFloat(1 - pow(1 - t, 3))
            self.updateShape(head: floating.center)
            if t >= 1 {
                self.shape.path = nil
                self.stopLink()
            }
        }
        if let floating {
            let wobble = CAKeyframeAnimation(keyPath: "transform.scale")
            wobble.values = [1.0, 1.18, 0.94, 1.03, 1.0]
            wobble.keyTimes = [0, 0.25, 0.55, 0.8, 1]
            wobble.duration = 0.35
            floating.layer.add(wobble, forKey: "wobble")
        }
    }

    // MARK: - Shape

    private func updateShape(head: CGPoint) {
        let dx = head.x - origin.x, dy = head.y - origin.y
        let distance = hypot(dx, dy)
        if detached {
            let r = radius * 0.45 * (1 - neckRetract)
            guard r > 0.5 else { shape.path = nil; return }
            let tipDistance = distance * 0.35 * (1 - neckRetract)
            let tip = CGPoint(x: origin.x + dx / max(distance, 1) * tipDistance, y: origin.y + dy / max(distance, 1) * tipDistance)
            shape.path = Self.gooeyPath(from: origin, r1: r, to: tip, r2: r * 0.6, neck: 0.5)
            return
        }
        let k = min(distance / snapDistance, 1)
        let anchorRadius = radius * (1 - 0.4 * k)
        shape.path = Self.gooeyPath(from: origin, r1: anchorRadius, to: head, r2: radius, neck: 1 - k)
    }

    static func gooeyPath(from c1: CGPoint, r1: CGFloat, to c2: CGPoint, r2: CGFloat, neck: CGFloat) -> CGPath {
        let path = UIBezierPath()
        let dx = c2.x - c1.x, dy = c2.y - c1.y
        let d = hypot(dx, dy)
        guard d > 0.5 else {
            path.addArc(withCenter: c1, radius: max(r1, r2), startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            return path.cgPath
        }
        let angle = atan2(dy, dx)
        let perp = angle + .pi / 2
        func on(_ c: CGPoint, _ r: CGFloat, _ a: CGFloat) -> CGPoint { CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)) }
        let p1a = on(c1, r1, perp), p1b = on(c1, r1, perp - .pi)
        let p2a = on(c2, r2, perp), p2b = on(c2, r2, perp - .pi)
        // Two control points near the middle pinch the neck like a stretching drop.
        let halfWidth = min(r1, r2) * (0.12 + 0.68 * max(0, min(neck, 1)))
        func along(_ t: CGFloat) -> CGPoint { CGPoint(x: c1.x + dx * t, y: c1.y + dy * t) }
        let a1 = on(along(0.38), halfWidth, perp), a2 = on(along(0.62), halfWidth, perp)
        let b1 = on(along(0.62), halfWidth, perp - .pi), b2 = on(along(0.38), halfWidth, perp - .pi)

        path.move(to: p1b)
        path.addArc(withCenter: c1, radius: r1, startAngle: perp - .pi, endAngle: perp - 2 * .pi, clockwise: false)
        path.addCurve(to: p2a, controlPoint1: a1, controlPoint2: a2)
        path.addArc(withCenter: c2, radius: r2, startAngle: perp, endAngle: perp - .pi, clockwise: false)
        path.addCurve(to: p1b, controlPoint1: b1, controlPoint2: b2)
        path.close()
        _ = p1a
        _ = p2b
        return path.cgPath
    }

    private static func stretch(angle: CGFloat, along: CGFloat, across: CGFloat) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: angle).scaledBy(x: along, y: across).rotated(by: -angle)
    }

    // MARK: - Pop

    public static func pop(at point: CGPoint, in container: UIView, color: UIColor, radius: CGFloat) {
        let ring = CAShapeLayer()
        ring.path = UIBezierPath(arcCenter: .zero, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath
        ring.position = point
        ring.fillColor = nil
        ring.strokeColor = color.cgColor
        ring.lineWidth = 3
        container.layer.addSublayer(ring)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.8
        grow.toValue = 2.6
        let thin = CABasicAnimation(keyPath: "lineWidth")
        thin.fromValue = 4
        thin.toValue = 0.2
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, thin, fade]
        group.duration = 0.32
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        ring.add(group, forKey: "pop")

        let count = 10
        var droplets: [UIView] = []
        for i in 0..<count {
            let size = CGFloat.random(in: radius * 0.35 ... radius * 0.75)
            let drop = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
            drop.backgroundColor = color
            drop.layer.cornerRadius = size / 2
            drop.center = point
            container.addSubview(drop)
            droplets.append(drop)
            let angle = CGFloat(i) / CGFloat(count) * 2 * .pi + CGFloat.random(in: -0.25...0.25)
            let distance = CGFloat.random(in: radius * 1.8 ... radius * 3.6)
            UIView.animate(withDuration: 0.42, delay: 0, options: [.curveEaseOut]) {
                drop.center = CGPoint(x: point.x + cos(angle) * distance, y: point.y + sin(angle) * distance + 6)
                drop.transform = CGAffineTransform(scaleX: 0.15, y: 0.15)
                drop.alpha = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ring.removeFromSuperlayer()
            droplets.forEach { $0.removeFromSuperview() }
        }
    }

    // MARK: - Display link

    private var linkAction: (() -> Void)?

    private func startLink(_ action: @escaping () -> Void) {
        linkAction = action
        guard link == nil else { return }
        let link = CADisplayLink(target: StretchyBadgeLinkTarget { [weak self] in self?.linkAction?() }, selector: #selector(StretchyBadgeLinkTarget.fire))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
        linkAction = nil
    }

    // MARK: - UIGestureRecognizerDelegate

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        badgeView.alpha > 0 && !badgeView.isHidden
    }
}

private final class StretchyBadgeLinkTarget {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}
