import UIKit
import Display
import TelegramCore
import StretchyBadge

extension ChatListItemNode {
    func updateStretchyBadge(item: ChatListItem, hasUnread: Bool, isMuted: Bool) {
        if self.stretchyBadgeRecognizer == nil {
            let recognizer = StretchyBadgeDragRecognizer(targetAt: { [weak self] point in
                return self?.stretchyBadgeTarget(at: point)
            })
            self.view.addGestureRecognizer(recognizer)
            self.stretchyBadgeRecognizer = recognizer
        }
        guard hasUnread, !item.editing, case let .peer(peerData) = item.content else {
            self.stretchyBadgeInfo = nil
            return
        }
        let peerId = peerData.peer.peerId
        let context = item.context
        let theme = item.presentationData.theme.chatList
        self.stretchyBadgeInfo = (
            color: isMuted ? theme.unreadBadgeInactiveBackgroundColor : theme.unreadBadgeActiveBackgroundColor,
            onPop: {
                // The same call as "Mark as Read" in the chat list context menu (ChatContextMenus.swift).
                let _ = context.engine.messages.togglePeersUnreadMarkInteractively(peerIds: [peerId], setToValue: nil).startStandalone()
            }
        )
    }

    func stretchyBadgeTarget(at point: CGPoint) -> StretchyBadgeDragRecognizer.Target? {
        guard let info = self.stretchyBadgeInfo, self.revealOffset == 0.0 else {
            return nil
        }
        let badgeView = self.badgeNode.view
        let grabArea = badgeView.convert(badgeView.bounds, to: self.view).insetBy(dx: -18.0, dy: -14.0)
        guard grabArea.contains(point) else {
            return nil
        }
        return StretchyBadgeDragRecognizer.Target(badge: badgeView, mirror: nil, color: info.color, onPop: info.onPop)
    }
}
