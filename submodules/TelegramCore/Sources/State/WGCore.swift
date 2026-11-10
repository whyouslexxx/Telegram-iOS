// MARK: Whygram
import Foundation
import Postbox
import SGSimpleSettings

private func wgIsBotAuthor(_ message: Message) -> Bool {
    if let author = message.author as? TelegramUser, author.botInfo != nil {
        return true
    }
    return false
}

/// Запись о правке: что было в сообщении до того, как сервер прислал новый текст.
/// Возвращает nil, если записывать нечего.
func wgAttributeRecordingEdit(previous: Message, updatedText: String) -> WGMessageAttribute? {
    guard WGSettings.shared.saveEdits else {
        return nil
    }
    if previous.text == updatedText || previous.text.isEmpty {
        return nil
    }
    if previous.id.namespace != Namespaces.Message.Cloud {
        return nil
    }
    if !WGSettings.shared.saveFromBots && wgIsBotAuthor(previous) {
        return nil
    }
    let current = previous.wgAttribute
    var edits = current?.edits ?? []
    if let last = edits.last, last.text == previous.text {
        return nil
    }
    edits.append(WGMessageAttribute.Edit(text: previous.text, date: Int32(Date().timeIntervalSince1970)))
    if edits.count > WGMessageAttribute.maxEdits {
        edits.removeFirst(edits.count - WGMessageAttribute.maxEdits)
    }
    return WGMessageAttribute(deletedDate: current?.deletedDate, edits: edits)
}

private func wgShouldKeepDeletedMessage(_ message: Message, saveFromBots: Bool) -> Bool {
    // Свои сообщения удаляются как обычно: их удалил сам пользователь.
    if !message.flags.contains(.Incoming) {
        return false
    }
    for media in message.media {
        if media is TelegramMediaAction {
            return false
        }
    }
    // Исчезающие сообщения и сообщения с таймером автоудаления не сохраняются.
    for attribute in message.attributes {
        if attribute is AutoremoveTimeoutMessageAttribute || attribute is AutoclearTimeoutMessageAttribute {
            return false
        }
    }
    if !saveFromBots && wgIsBotAuthor(message) {
        return false
    }
    return true
}

/// Сервер сообщил об удалении сообщений. Те, что нужно сохранить, помечаются удалёнными
/// и остаются в базе. Возвращает идентификаторы, которые действительно надо удалить.
func wgMarkRemotelyDeletedMessages(transaction: Transaction, ids: [MessageId]) -> [MessageId] {
    guard WGSettings.shared.saveDeleted else {
        return ids
    }
    let saveFromBots = WGSettings.shared.saveFromBots
    let timestamp = Int32(Date().timeIntervalSince1970)
    var idsToDelete: [MessageId] = []
    for id in ids {
        guard id.namespace == Namespaces.Message.Cloud, let message = transaction.getMessage(id) else {
            idsToDelete.append(id)
            continue
        }
        if message.wgIsDeleted {
            continue
        }
        if !wgShouldKeepDeletedMessage(message, saveFromBots: saveFromBots) {
            idsToDelete.append(id)
            continue
        }
        transaction.updateMessage(id, update: { currentMessage in
            var attributes = currentMessage.attributes
            let edits = currentMessage.wgAttribute?.edits ?? []
            attributes.removeAll(where: { $0 is WGMessageAttribute })
            attributes.append(WGMessageAttribute(deletedDate: timestamp, edits: edits))
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
        })
    }
    return idsToDelete
}

/// Короткое описание сообщения без текста для цитаты: «Голосовое сообщение», «Фото» и так далее.
private func wgMediaDescription(_ message: Message) -> String {
    let lang = Locale.preferredLanguages.first ?? "en"
    for media in message.media {
        if let file = media as? TelegramMediaFile {
            if file.isVoice {
                return wgString("Quote.Voice", lang)
            } else if file.isInstantVideo {
                return wgString("Quote.Round", lang)
            } else if file.isSticker {
                return wgString("Quote.Sticker", lang)
            } else if file.isVideo {
                return wgString("Quote.Video", lang)
            } else if file.isMusic {
                return wgString("Quote.Music", lang)
            } else {
                return wgString("Quote.File", lang)
            }
        } else if media is TelegramMediaImage {
            return wgString("Quote.Photo", lang)
        }
    }
    if !message.media.isEmpty {
        return wgString("Quote.Media", lang)
    }
    return ""
}

/// Ответ на сообщение, которое собеседник уже удалил: на сервере его нет, поэтому ответ
/// отправляется обычным сообщением с цитатой удалённого текста. В группах перед цитатой
/// ставится автор: «@alex: привет».
func wgQuoteReplyToDeletedMessage(transaction: Transaction, peerId: PeerId, message: EnqueueMessage) -> EnqueueMessage {
    guard case let .message(text, attributes, inlineStickers, mediaReference, threadId: threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message else {
        return message
    }
    guard let replySubject = replyToMessageId, let repliedMessage = transaction.getMessage(replySubject.messageId), repliedMessage.wgIsDeleted else {
        return message
    }

    var quotedText = replySubject.quote?.text ?? repliedMessage.text
    quotedText = quotedText.trimmingCharacters(in: .whitespacesAndNewlines)
    if quotedText.isEmpty {
        quotedText = wgMediaDescription(repliedMessage)
    }
    if quotedText.count > 200 {
        quotedText = String(quotedText.prefix(200)) + "…"
    }
    // Стикер или медиа без подписи цитату нести не могут: отправляем без ответа.
    if quotedText.isEmpty || (mediaReference != nil && text.isEmpty) {
        return .message(text: text, attributes: attributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: nil, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
    }

    var prefix = ""
    if peerId.namespace != Namespaces.Peer.CloudUser, let author = repliedMessage.author {
        if let username = author.addressName, !username.isEmpty {
            prefix = "@\(username): "
        } else {
            prefix = "\(author.debugDisplayTitle): "
        }
    }
    let quote = prefix + quotedText
    let quoteLength = (quote as NSString).length
    let shift = quoteLength + 1

    var updatedAttributes: [MessageAttribute] = []
    var entities: [MessageTextEntity] = [MessageTextEntity(range: 0 ..< quoteLength, type: .BlockQuote(isCollapsed: false))]
    for attribute in attributes {
        if let attribute = attribute as? TextEntitiesMessageAttribute {
            for entity in attribute.entities {
                entities.append(MessageTextEntity(range: (entity.range.lowerBound + shift) ..< (entity.range.upperBound + shift), type: entity.type))
            }
        } else {
            updatedAttributes.append(attribute)
        }
    }
    updatedAttributes.append(TextEntitiesMessageAttribute(entities: entities))

    return .message(text: quote + "\n" + text, attributes: updatedAttributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: nil, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
}

/// Отправка через отложенные сообщения: сервер сам отправит сообщение через несколько секунд,
/// и аккаунт не появится в сети.
func wgPreparedOutgoingMessages(accountPeerId: PeerId, peerId: PeerId, messages: [EnqueueMessage]) -> [EnqueueMessage] {
    guard WGSettings.shared.ghostSendScheduled else {
        return messages
    }
    if peerId == accountPeerId || peerId.namespace == Namespaces.Peer.SecretChat {
        return messages
    }
    let scheduleTime = Int32(Date().timeIntervalSince1970) + 12
    return messages.map { message -> EnqueueMessage in
        return message.withUpdatedAttributes { attributes in
            if attributes.contains(where: { $0 is OutgoingScheduleInfoMessageAttribute }) {
                return attributes
            }
            var attributes = attributes
            attributes.append(OutgoingScheduleInfoMessageAttribute(scheduleTime: scheduleTime, repeatPeriod: nil))
            return attributes
        }
    }
}
