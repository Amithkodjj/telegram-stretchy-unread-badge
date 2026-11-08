import UIKit
import UIKit.UIGestureRecognizerSubclass

public final class StretchyBadgeDragRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    public struct Target {
        public let badge: UIView
        public let mirror: UIView?
        public let color: UIColor
        public let onPop: () -> Void

        public init(badge: UIView, mirror: UIView?, color: UIColor, onPop: @escaping () -> Void) {
            self.badge = badge
            self.mirror = mirror
            self.color = color
            self.onPop = onPop
        }
    }

    private static let startDistance: CGFloat = 3.0

    /// A popped counter stays hidden this long, so it never flashes before the new count arrives.
    private static let restoreDelayAfterPop: Double = 1.5

    private let targetAt: (CGPoint) -> Target?
    private var pendingTarget: Target?
    private var startPoint: CGPoint = .zero
    private var trackedTouch: UITouch?
    private var controller: StretchyBadgeController?
    private var target: Target?
    private var popped = false

    public init(targetAt: @escaping (CGPoint) -> Target?) {
        self.targetAt = targetAt
        super.init(target: nil, action: nil)
        self.addTarget(self, action: #selector(self.handleDrag))
        self.delegate = self
    }

    override public func reset() {
        super.reset()
        self.pendingTarget = nil
        self.trackedTouch = nil
    }

    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard self.trackedTouch == nil, let view = self.view, let touch = touches.first,
              let target = self.targetAt(touch.location(in: view)) else {
            if self.trackedTouch == nil {
                self.state = .failed
            }
            return
        }
        self.trackedTouch = touch
        self.pendingTarget = target
        self.startPoint = touch.location(in: nil)
    }

    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = self.trackedTouch, touches.contains(touch) else {
            return
        }
        if self.state == .possible {
            let point = touch.location(in: nil)
            if hypot(point.x - self.startPoint.x, point.y - self.startPoint.y) >= Self.startDistance {
                self.state = .began
            }
        } else {
            self.state = .changed
        }
    }

    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let touch = self.trackedTouch, touches.contains(touch) else {
            return
        }
        self.state = self.state == .possible ? .failed : .ended
    }

    override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard let touch = self.trackedTouch, touches.contains(touch) else {
            return
        }
        self.state = self.state == .possible ? .failed : .cancelled
    }

    override public func location(in view: UIView?) -> CGPoint {
        return self.trackedTouch?.location(in: view) ?? super.location(in: view)
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc private func handleDrag() {
        guard let window = self.view?.window else {
            return
        }
        switch self.state {
        case .began:
            guard let target = self.pendingTarget else {
                return
            }
            let controller = StretchyBadgeController(badgeView: target.badge, container: window, color: target.color, installsGesture: false)
            self.popped = false
            controller.snapDistance = 56.0
            controller.popDistance = 30.0
            controller.onPop = { [weak self] in
                self?.popped = true
                target.onPop()
            }
            self.controller = controller
            self.target = target
            target.mirror?.alpha = 0.0
            controller.beginDrag()
            controller.updateDrag(to: self.location(in: window))
        case .changed:
            self.controller?.updateDrag(to: self.location(in: window))
        case .ended, .cancelled:
            guard let controller = self.controller, let target = self.target else {
                return
            }
            controller.endDrag(at: self.location(in: window))
            let delay = self.popped ? Self.restoreDelayAfterPop : 0.7
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                target.mirror?.alpha = 1.0
                target.badge.alpha = 1.0
                if self?.controller === controller {
                    self?.controller = nil
                    self?.target = nil
                }
            }
        default:
            break
        }
    }
}
