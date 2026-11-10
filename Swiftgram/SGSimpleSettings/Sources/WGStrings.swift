// MARK: Whygram
import Foundation

private let wgRussian: [String: String] = [
    "Common.On": "Вкл",
    "Common.Off": "Выкл",
    "Common.Delete": "Удалить",
    "Common.Cancel": "Отмена",

    "Main.Ghost": "Режим призрака",
    "Main.Saving": "Сохранение сообщений",
    "Main.Filters": "Фильтры",
    "Main.Other": "Реклама и ограничения",
    "Main.Interface": "Интерфейс и поведение",
    "Main.Interface.Header": "SWIFTGRAM",
    "Main.Notice": "Whygram — неофициальный клиент. Часть функций нарушает условия Telegram для сторонних клиентов, поэтому риск для аккаунта есть. Данные хранятся только на этом устройстве.",

    "Ghost.Enable": "Режим призрака",
    "Ghost.Enable.Notice": "Скрывает вашу активность от собеседников. Ниже можно выбрать, что именно скрывать. Это не гарантия анонимности: сообщения, реакции и звонки всё равно выдают присутствие.",
    "Ghost.Hide.Header": "ЧТО СКРЫВАТЬ",
    "Ghost.NoRead": "Не читать сообщения",
    "Ghost.NoStoryViews": "Не отмечать истории",
    "Ghost.NoOnline": "Не показывать «в сети»",
    "Ghost.NoTyping": "Не показывать «печатает»",
    "Ghost.Hide.Notice": "С выключенным чтением чаты остаются непрочитанными и у вас. Отметить чат прочитанным можно долгим нажатием на него в списке чатов. Прослушивание голосовых тоже не отмечается.",
    "Ghost.Behavior.Header": "ПОВЕДЕНИЕ",
    "Ghost.AutoOffline": "Автоматически уходить в офлайн",
    "Ghost.ReadOnInteract": "Читать при отправке сообщения",
    "Ghost.SendScheduled": "Отправлять через отложенные",
    "Ghost.SendScheduled.Notice": "Сообщение уходит как отложенное и доставляется примерно через 12 секунд. Так аккаунт не появляется в сети при отправке. До доставки сообщение видно в отложенных.",
    "Ghost.StoryWarn": "Спрашивать перед просмотром истории",

    "Saving.Header": "ЧТО СОХРАНЯТЬ",
    "Saving.Deleted": "Удалённые сообщения",
    "Saving.Edits": "Историю правок",
    "Saving.Bots": "Сохранять в чатах с ботами",
    "Saving.Notice": "Если собеседник удалит сообщение, оно останется в чате с пометкой «удалено». Чтобы посмотреть прежние версии изменённого сообщения, нажмите на него и выберите «История правок».",
    "Saving.Limits": "Сохраняется только то, что это устройство успело получить. Свои сообщения, исчезающие сообщения и сообщения с таймером автоудаления не сохраняются. Убрать сохранённое сообщение можно обычным удалением.",

    "Filters.Enable": "Фильтры сообщений",
    "Filters.Enable.Notice": "Входящие сообщения, текст которых подходит под фильтр, скрываются только у вас.",
    "Filters.Global.Header": "ДЛЯ ВСЕХ ЧАТОВ",
    "Filters.Chats.Header": "ДЛЯ ОТДЕЛЬНЫХ ЧАТОВ",
    "Filters.Add": "Добавить фильтр",
    "Filters.Add.Title": "Новый фильтр",
    "Filters.Add.Placeholder": "Слово или фраза",
    "Filters.Add.Notice": "Обычный фильтр — слово или фраза, регистр не важен. Регулярное выражение начинается с re:, например re:розыгрыш|giveaway. Фильтр для одного чата добавляется из меню сообщения.",
    "Filters.Scope.All": "Для всех чатов",
    "Filters.Scope.Chat": "Только для этого чата",
    "Filters.Blocked": "Скрывать заблокированных",
    "Filters.Blocked.Notice": "Сообщения заблокированных пользователей скрываются в группах. Сейчас в списке: %@.",

    "Other.Ads.Header": "РЕКЛАМА",
    "Other.NoAds": "Скрывать рекламу Telegram",
    "Other.NoAds.Notice": "Убирает спонсорские сообщения в каналах и ботах. Рекламные посты самих авторов можно скрыть фильтром.",
    "Other.Restrictions.Header": "ОГРАНИЧЕНИЯ",
    "Other.CopyProtection": "Разрешить копирование из защищённых каналов",
    "Other.CopyProtection.Notice": "Позволяет копировать текст и сохранять медиа в каналах и группах, где автор запретил сохранение. Пересылка таких сообщений остаётся ограничена сервером. Уважайте права авторов.",

    "Message.Deleted": "удалено",
    "ContextMenu.EditHistory": "История правок",
    "ContextMenu.AddFilter": "Скрывать похожие",
    "EditHistory.Title": "История правок",
    "EditHistory.Current": "ТЕКУЩАЯ ВЕРСИЯ",
    "EditHistory.Before": "ДО ПРАВКИ %@",
    "EditHistory.Empty": "(без текста)"
]

private let wgEnglish: [String: String] = [
    "Common.On": "On",
    "Common.Off": "Off",
    "Common.Delete": "Delete",
    "Common.Cancel": "Cancel",

    "Main.Ghost": "Ghost Mode",
    "Main.Saving": "Message Saving",
    "Main.Filters": "Filters",
    "Main.Other": "Ads and Restrictions",
    "Main.Interface": "Interface and Behavior",
    "Main.Interface.Header": "SWIFTGRAM",
    "Main.Notice": "Whygram is an unofficial client. Some features go against Telegram's terms for third-party clients, so there is a risk to your account. All data stays on this device.",

    "Ghost.Enable": "Ghost Mode",
    "Ghost.Enable.Notice": "Hides your activity from other people. Choose below what to hide. This is not a guarantee of anonymity: messages, reactions and calls still reveal that you are here.",
    "Ghost.Hide.Header": "WHAT TO HIDE",
    "Ghost.NoRead": "Don't Read Messages",
    "Ghost.NoStoryViews": "Don't Mark Stories as Viewed",
    "Ghost.NoOnline": "Don't Show Online",
    "Ghost.NoTyping": "Don't Show Typing",
    "Ghost.Hide.Notice": "With reading turned off, chats stay unread for you too. To mark a chat as read, long-press it in the chat list. Listening to voice messages is not reported either.",
    "Ghost.Behavior.Header": "BEHAVIOR",
    "Ghost.AutoOffline": "Go Offline Automatically",
    "Ghost.ReadOnInteract": "Read When Sending a Message",
    "Ghost.SendScheduled": "Send via Scheduled Messages",
    "Ghost.SendScheduled.Notice": "The message is sent as a scheduled one and delivered in about 12 seconds, so your account does not appear online. Until then it is listed in scheduled messages.",
    "Ghost.StoryWarn": "Ask Before Viewing a Story",

    "Saving.Header": "WHAT TO SAVE",
    "Saving.Deleted": "Deleted Messages",
    "Saving.Edits": "Edit History",
    "Saving.Bots": "Save in Chats with Bots",
    "Saving.Notice": "If someone deletes a message, it stays in the chat marked as deleted. To see earlier versions of an edited message, tap it and choose Edit History.",
    "Saving.Limits": "Only what this device has received is saved. Your own messages, disappearing messages and messages with an auto-delete timer are not saved. To remove a saved message, delete it as usual.",

    "Filters.Enable": "Message Filters",
    "Filters.Enable.Notice": "Incoming messages whose text matches a filter are hidden only for you.",
    "Filters.Global.Header": "FOR ALL CHATS",
    "Filters.Chats.Header": "FOR SPECIFIC CHATS",
    "Filters.Add": "Add Filter",
    "Filters.Add.Title": "New Filter",
    "Filters.Add.Placeholder": "Word or phrase",
    "Filters.Add.Notice": "A plain filter is a word or phrase, case-insensitive. A regular expression starts with re:, for example re:giveaway|promo. A filter for one chat is added from the message menu.",
    "Filters.Scope.All": "For All Chats",
    "Filters.Scope.Chat": "Only for This Chat",
    "Filters.Blocked": "Hide Blocked Users",
    "Filters.Blocked.Notice": "Messages from blocked users are hidden in groups. Currently in the list: %@.",

    "Other.Ads.Header": "ADS",
    "Other.NoAds": "Hide Telegram Ads",
    "Other.NoAds.Notice": "Removes sponsored messages in channels and bots. Ads posted by channel authors can be hidden with a filter.",
    "Other.Restrictions.Header": "RESTRICTIONS",
    "Other.CopyProtection": "Allow Copying from Protected Channels",
    "Other.CopyProtection.Notice": "Lets you copy text and save media in channels and groups where the author disabled saving. Forwarding such messages is still limited by the server. Respect the authors' rights.",

    "Message.Deleted": "deleted",
    "ContextMenu.EditHistory": "Edit History",
    "ContextMenu.AddFilter": "Hide Similar",
    "EditHistory.Title": "Edit History",
    "EditHistory.Current": "CURRENT VERSION",
    "EditHistory.Before": "BEFORE EDIT %@",
    "EditHistory.Empty": "(no text)"
]

/// Строка интерфейса Whygram. Русский для русскоязычного интерфейса, английский для остальных.
public func wgString(_ key: String, _ languageCode: String) -> String {
    let table = languageCode.hasPrefix("ru") || languageCode.hasPrefix("uk") || languageCode.hasPrefix("be") ? wgRussian : wgEnglish
    return table[key] ?? wgEnglish[key] ?? key
}

public func wgString(_ key: String, _ languageCode: String, _ argument: String) -> String {
    return wgString(key, languageCode).replacingOccurrences(of: "%@", with: argument)
}
