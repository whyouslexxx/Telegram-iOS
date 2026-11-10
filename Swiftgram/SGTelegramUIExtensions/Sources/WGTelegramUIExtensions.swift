// MARK: Whygram
import SGSimpleSettings
import WGSettingsUI
//
import AccountContext
import AppBundle
import ContextUI
import Display
import Foundation
import Postbox
import TelegramCore
import TelegramPresentationData
import UIKit
import ChatControllerInteraction
import ChatPresentationInterfaceState

/// Скрывать ли сообщение в ленте чата: фильтры по тексту и заблокированные пользователи.
/// Действует только на входящие сообщения и только в этом клиенте.
func wgShouldHideMessage(_ message: Message, accountPeerId: PeerId) -> Bool {
    if !message.flags.contains(.Incoming) {
        return false
    }
    let settings = WGSettings.shared
    if settings.hideBlocked, let authorId = message.author?.id, authorId != accountPeerId, authorId != message.id.peerId, authorId.namespace == Namespaces.Peer.CloudUser {
        if settings.isPeerBlocked(authorId.toInt64()) {
            return true
        }
    }
    if !message.text.isEmpty && settings.textMatchesFilters(message.text, peerId: message.id.peerId.toInt64()) {
        return true
    }
    return false
}

func wgAppendContextMenuActions(actions: inout [ContextMenuItem], sgActions: inout [ContextMenuItem], context: AccountContext, message: EngineRawMessage, controllerInteraction: ChatControllerInteraction, chatPresentationInterfaceState: ChatPresentationInterfaceState) {
    let lang = chatPresentationInterfaceState.strings.baseLanguageCode

    if let attribute = message.wgAttribute, !attribute.edits.isEmpty {
        actions.append(.action(ContextMenuActionItem(text: wgString("ContextMenu.EditHistory", lang), icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "WGHistory"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            controllerInteraction.navigationController()?.pushViewController(wgEditHistoryController(context: context, currentText: message.text, edits: attribute.edits))
            f(.default)
        })))
    }

    let chatPeerId = message.id.peerId.toInt64()
    let chatTitle = message.peers[message.id.peerId]?.debugDisplayTitle ?? ""
    if WGSettings.shared.ghostNoRead && message.id.peerId != context.account.peerId {
        let isException = WGSettings.shared.isReadException(chatPeerId)
        sgActions.append(.action(ContextMenuActionItem(text: wgString(isException ? "ContextMenu.ReadException.Remove" : "ContextMenu.ReadException.Add", lang), icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: isException ? "WGEyeOff" : "WGGhost"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            WGSettings.shared.rememberPeerTitle(chatPeerId, title: chatTitle)
            WGSettings.shared.setReadException(chatPeerId, !isException)
            f(.default)
        })))
    }

    if !message.text.isEmpty && message.flags.contains(.Incoming) {
        sgActions.append(.action(ContextMenuActionItem(text: wgString("ContextMenu.AddFilter", lang), icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "WGFilterAdd"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            WGSettings.shared.rememberPeerTitle(chatPeerId, title: chatTitle)
            wgPresentAddFilter(context: context, peerId: chatPeerId, text: message.text, present: { controller, arguments in
                controllerInteraction.presentController(controller, arguments)
            })
        })))
    }
}

/// Заставка при запуске: на чёрном фоне появляется «W», из неё выезжают остальные буквы «Whygram».
/// Показывается поверх окна, пока приложение загружается, и не перехватывает нажатия.
func wgShowLaunchAnimation(in window: UIWindow) {
    let overlay = UIView(frame: window.bounds)
    overlay.backgroundColor = .black
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlay.isUserInteractionEnabled = false
    overlay.layer.zPosition = 100000.0

    let font = UIFont.systemFont(ofSize: 46.0, weight: .bold)
    let label = UILabel()
    label.text = "Whygram"
    label.font = font
    label.textColor = .white
    label.sizeToFit()

    let fullSize = label.bounds.size
    let firstLetterWidth = ceil(("W" as NSString).size(withAttributes: [NSAttributedString.Key.font: font]).width)

    let container = UIView(frame: CGRect(origin: CGPoint(), size: CGSize(width: firstLetterWidth, height: fullSize.height)))
    container.clipsToBounds = true
    container.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
    container.center = CGPoint(x: overlay.bounds.midX, y: overlay.bounds.midY)
    label.frame = CGRect(origin: CGPoint(), size: fullSize)
    container.addSubview(label)
    overlay.addSubview(container)
    window.addSubview(overlay)

    container.alpha = 0.0
    container.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)

    UIView.animate(withDuration: 0.35, delay: 0.0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.0, options: [], animations: {
        container.alpha = 1.0
        container.transform = .identity
    }, completion: { _ in
        UIView.animate(withDuration: 0.6, delay: 0.1, usingSpringWithDamping: 0.86, initialSpringVelocity: 0.0, options: [], animations: {
            container.bounds = CGRect(origin: CGPoint(), size: fullSize)
        }, completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 0.4, options: [], animations: {
                overlay.alpha = 0.0
            }, completion: { _ in
                overlay.removeFromSuperview()
            })
        })
    })
}
