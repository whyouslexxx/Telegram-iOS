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
            controllerInteraction.navigationController()?.pushViewController(wgEditHistoryController(context: context, message: message))
            f(.default)
        })))
    }

    if !message.text.isEmpty && message.flags.contains(.Incoming) {
        sgActions.append(.action(ContextMenuActionItem(text: wgString("ContextMenu.AddFilter", lang), icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "WGFilterAdd"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            wgPresentAddFilter(context: context, peerId: message.id.peerId, text: message.text, present: { controller, arguments in
                controllerInteraction.presentController(controller, arguments)
            })
        })))
    }
}
