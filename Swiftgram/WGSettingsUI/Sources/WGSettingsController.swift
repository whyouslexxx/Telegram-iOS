// MARK: Whygram
import Foundation
import UIKit
import UserNotifications
import SGAppGroupIdentifier
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import ItemListUI
import PresentationDataUtils
import AccountContext
import AppBundle
import PromptUI
import TextFormat
import SGSimpleSettings
import SGSettingsUI

// MARK: - Список

private final class WGArguments {
    let setBool: (String, Bool) -> Void
    let open: (String) -> Void

    init(setBool: @escaping (String, Bool) -> Void = { _, _ in }, open: @escaping (String) -> Void = { _ in }) {
        self.setBool = setBool
        self.open = open
    }
}

private enum WGEntry: ItemListNodeEntry {
    case header(id: Int, section: Int32, text: String)
    case toggle(id: Int, section: Int32, key: String, title: String, value: Bool, enabled: Bool)
    case notice(id: Int, section: Int32, text: String)
    case link(id: Int, section: Int32, key: String, title: String, label: String, icon: String?, color: UInt32)
    case action(id: Int, section: Int32, key: String, title: String, destructive: Bool)
    case text(id: Int, section: Int32, key: String, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _):
            return section
        case let .toggle(_, section, _, _, _, _):
            return section
        case let .notice(_, section, _):
            return section
        case let .link(_, section, _, _, _, _, _):
            return section
        case let .action(_, section, _, _, _):
            return section
        case let .text(_, section, _, _):
            return section
        }
    }

    var stableId: Int {
        switch self {
        case let .header(id, _, _):
            return id
        case let .toggle(id, _, _, _, _, _):
            return id
        case let .notice(id, _, _):
            return id
        case let .link(id, _, _, _, _, _, _):
            return id
        case let .action(id, _, _, _, _):
            return id
        case let .text(id, _, _, _):
            return id
        }
    }

    static func <(lhs: WGEntry, rhs: WGEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! WGArguments
        switch self {
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(_, _, key, title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setBool(key, value)
            })
        case let .notice(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .link(_, _, key, title, label, icon, color):
            var iconImage: UIImage?
            if let icon {
                iconImage = wgSettingsIcon(icon, color: color)
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: iconImage, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.open(key)
            })
        case let .action(_, _, key, title, destructive):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: destructive ? .destructive : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.open(key)
            })
        case let .text(_, _, key, text):
            return ItemListMultilineTextItem(presentationData: presentationData, text: text, enabledEntityTypes: [], sectionId: self.section, style: .blocks, action: {
                arguments.open(key)
            })
        }
    }
}

private let wgIconCacheLock = NSLock()
private var wgIconCache: [String: UIImage] = [:]

/// Иконка раздела: белый глиф Lucide на цветной плашке, как в настройках Telegram.
private func wgSettingsIcon(_ name: String, color: UInt32) -> UIImage? {
    let cacheKey = "\(name)-\(color)"
    wgIconCacheLock.lock()
    let cached = wgIconCache[cacheKey]
    wgIconCacheLock.unlock()
    if let cached {
        return cached
    }
    let image = renderSettingsIcon(name: name, scaleFactor: 18.0 / 24.0, backgroundColors: [UIColor(rgb: color)])
    if let image {
        wgIconCacheLock.lock()
        wgIconCache[cacheKey] = image
        wgIconCacheLock.unlock()
    }
    return image
}

private final class WGRefresh {
    private var counter: Int = 0
    private let promise = ValuePromise<Int>(0, ignoreRepeated: false)

    var signal: Signal<Int, NoError> {
        return self.promise.get()
    }

    func trigger() {
        self.counter += 1
        self.promise.set(self.counter)
    }
}

private func wgListController(context: AccountContext, title: @escaping (String) -> String, refresh: WGRefresh, arguments: WGArguments, entries: @escaping (PresentationData) -> [WGEntry]) -> ItemListController {
    let signal = combineLatest(context.sharedContext.presentationData, refresh.signal)
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title(presentationData.strings.baseLanguageCode)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries(presentationData), style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controllerState, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.didAppear = { _ in
        refresh.trigger()
    }
    return controller
}

private func wgSetBool(_ key: String, _ value: Bool) {
    if let settingKey = WGSettings.Key(rawValue: key) {
        WGSettings.shared.set(settingKey, value)
    } else if key == "warnOnStoriesOpen" {
        SGSimpleSettings.shared.warnOnStoriesOpen = value
    }
}

private func wgToggle(_ id: Int, _ section: Int32, _ key: WGSettings.Key, _ titleKey: String, _ lang: String, enabled: Bool = true) -> WGEntry {
    return .toggle(id: id, section: section, key: key.rawValue, title: wgString(titleKey, lang), value: WGSettings.shared.bool(key), enabled: enabled)
}

// MARK: - Главный экран

public func wgSettingsController(context: AccountContext) -> ViewController {
    let refresh = WGRefresh()
    var pushImpl: ((ViewController) -> Void)?

    let arguments = WGArguments(open: { key in
        switch key {
        case "ghost":
            pushImpl?(wgGhostController(context: context))
        case "saving":
            pushImpl?(wgSavingController(context: context))
        case "filters":
            pushImpl?(wgFiltersController(context: context))
        case "other":
            pushImpl?(wgOtherController(context: context))
        case "appearance":
            pushImpl?(wgAppearanceController(context: context))
        case "interface":
            pushImpl?(sgSettingsController(context: context))
        case "pushDiagnostics":
            pushImpl?(wgPushDiagnosticsController(context: context))
        default:
            break
        }
    })

    let controller = wgListController(context: context, title: { _ in "Whygram" }, refresh: refresh, arguments: arguments, entries: { presentationData in
        let lang = presentationData.strings.baseLanguageCode
        let settings = WGSettings.shared
        let on = wgString("Common.On", lang)
        let off = wgString("Common.Off", lang)
        let filtersCount = settings.globalFilters.count + settings.chatFilters.values.reduce(0, { $0 + $1.count })

        var entries: [WGEntry] = []
        entries.append(.link(id: 1, section: 0, key: "ghost", title: wgString("Main.Ghost", lang), label: settings.bool(.ghostMode) ? on : off, icon: "WGGhost", color: 0x5E5CE6))
        entries.append(.link(id: 2, section: 0, key: "saving", title: wgString("Main.Saving", lang), label: (settings.saveDeleted || settings.saveEdits) ? on : off, icon: "WGSaving", color: 0x34C759))
        entries.append(.link(id: 3, section: 0, key: "filters", title: wgString("Main.Filters", lang), label: settings.bool(.filtersEnabled) && filtersCount != 0 ? "\(filtersCount)" : "", icon: "WGFilter", color: 0xFF9F0A))
        entries.append(.link(id: 4, section: 0, key: "appearance", title: wgString("Main.Appearance", lang), label: "", icon: "WGPalette", color: 0xFF375F))
        entries.append(.link(id: 5, section: 0, key: "other", title: wgString("Main.Other", lang), label: "", icon: "WGShield", color: 0x0A84FF))

        entries.append(.header(id: 10, section: 1, text: wgString("Main.Interface.Header", lang)))
        entries.append(.link(id: 11, section: 1, key: "interface", title: wgString("Main.Interface", lang), label: "", icon: "WGInterface", color: 0x8E8E93))
        entries.append(.notice(id: 12, section: 1, text: wgString("Main.Notice", lang)))
        entries.append(.link(id: 20, section: 2, key: "pushDiagnostics", title: "Диагностика уведомлений", label: "", icon: "WGInterface", color: 0x0A84FF))
        return entries
    })
    pushImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

private func wgPushDiagnosticsController(context: AccountContext) -> ViewController {
    let refresh = WGRefresh()
    var systemStatus = "Проверка разрешений…"
    var refreshImpl: (() -> Void)?
    let arguments = WGArguments(open: { key in
        if key == "refresh" {
            refreshImpl?()
        } else if key == "register" {
            WGPushDiagnostics.record("apns", status: "Запрошена повторная регистрация")
            UIApplication.shared.registerForRemoteNotifications()
            context.sharedContext.updateNotificationTokensRegistration()
            refreshImpl?()
        } else if key == "localTest" {
            let content = UNMutableNotificationContent()
            content.title = "Whygram"
            content.body = "Локальные уведомления работают. Это проверка показа, а не доставки APNs."
            content.sound = .default
            let request = UNNotificationRequest(identifier: "whygram.push.local-test", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
            UNUserNotificationCenter.current().add(request) { error in
                WGPushDiagnostics.record("local-test", status: error.map { "Ошибка: \($0.localizedDescription)" } ?? "Локальное уведомление запланировано")
                DispatchQueue.main.async { refresh.trigger() }
            }
        }
    })
    refreshImpl = {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let enabled: (UNNotificationSetting) -> String = { $0 == .enabled ? "включено" : "выключено" }
            let report = "Разрешение: \(settings.authorizationStatus.rawValue)\nБаннеры: \(enabled(settings.alertSetting))\nЗвук: \(enabled(settings.soundSetting))\nЭкран блокировки: \(enabled(settings.lockScreenSetting))\nЦентр уведомлений: \(enabled(settings.notificationCenterSetting))\nЗначки: \(enabled(settings.badgeSetting))"
            DispatchQueue.main.async {
                systemStatus = report
                refresh.trigger()
            }
        }
    }
    let controller = wgListController(context: context, title: { _ in "Уведомления" }, refresh: refresh, arguments: arguments, entries: { _ in
        let shared = sgAppGroupBaseURL()
        let storage = shared == nil ? "Общая папка недоступна" : "Общая папка доступна"
        let keyExists = shared.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("telegram-data/.tempkey").path) } ?? false
        let timestamp = UserDefaults(suiteName: sgAppGroupIdentifier())?.double(forKey: "wg.push.receipt.\(sgBaseBundleIdentifier())") ?? 0
        let receipt = timestamp == 0 ? "Push ещё не зафиксирован расширением" : DateFormatter.localizedString(from: Date(timeIntervalSince1970: timestamp), dateStyle: .short, timeStyle: .medium)
        return [
            .header(id: 1, section: 0, text: "Разрешения iOS"),
            .text(id: 2, section: 0, key: "permissions", text: systemStatus),
            .header(id: 10, section: 1, text: "Регистрация push"),
            .text(id: 11, section: 1, key: "apns", text: "APNs:\n\(WGPushDiagnostics.status("apns"))"),
            .text(id: 12, section: 1, key: "telegram", text: "Telegram:\n\(WGPushDiagnostics.status("telegram.1.\(context.account.peerId.toInt64())"))"),
            .text(id: 13, section: 1, key: "environment", text: "Среда APNs: \(sgPushNotificationsUseSandbox() ? "sandbox" : "production")"),
            .text(id: 14, section: 1, key: "storage", text: "\(storage)\nКлюч базы: \(keyExists ? "есть" : "нет")\nПоследний запуск расширения:\n\(receipt)"),
            .header(id: 20, section: 2, text: "Проверка"),
            .action(id: 21, section: 2, key: "refresh", title: "Обновить результаты", destructive: false),
            .action(id: 22, section: 2, key: "register", title: "Повторить регистрацию push", destructive: false),
            .action(id: 23, section: 2, key: "localTest", title: "Тестовый баннер через 5 секунд", destructive: false),
            .text(id: 24, section: 2, key: "test", text: WGPushDiagnostics.status("local-test")),
            .notice(id: 25, section: 2, text: "Для теста сверни приложение. Затем вернись и обнови результаты. Локальный тест проверяет показ уведомлений без участия Telegram и APNs. Токены и содержимое сообщений здесь не сохраняются.")
        ]
    })
    controller.didAppear = { _ in refreshImpl?() }
    return controller
}

// MARK: - Режим призрака

private func wgGhostController(context: AccountContext) -> ViewController {
    let refresh = WGRefresh()
    var presentImpl: ((ViewController, Any?) -> Void)?

    let arguments = WGArguments(setBool: { key, value in
        wgSetBool(key, value)
        refresh.trigger()
    }, open: { key in
        guard key.hasPrefix("e:"), let peerId = Int64(key.dropFirst(2)) else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: wgString("Common.Delete", presentationData.strings.baseLanguageCode), color: .destructive, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    WGSettings.shared.setReadException(peerId, false)
                    refresh.trigger()
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        presentImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    })

    let controller = wgListController(context: context, title: { wgString("Main.Ghost", $0) }, refresh: refresh, arguments: arguments, entries: { presentationData in
        let lang = presentationData.strings.baseLanguageCode
        let settings = WGSettings.shared
        let master = settings.bool(.ghostMode)

        var entries: [WGEntry] = []
        entries.append(wgToggle(1, 0, .ghostMode, "Ghost.Enable", lang))
        entries.append(.notice(id: 2, section: 0, text: wgString("Ghost.Enable.Notice", lang)))

        entries.append(.header(id: 10, section: 1, text: wgString("Ghost.Hide.Header", lang)))
        entries.append(wgToggle(11, 1, .ghostNoRead, "Ghost.NoRead", lang, enabled: master))
        entries.append(wgToggle(12, 1, .ghostNoStoryViews, "Ghost.NoStoryViews", lang, enabled: master))
        entries.append(wgToggle(13, 1, .ghostNoOnline, "Ghost.NoOnline", lang, enabled: master))
        entries.append(wgToggle(14, 1, .ghostNoTyping, "Ghost.NoTyping", lang, enabled: master))
        entries.append(.notice(id: 15, section: 1, text: wgString("Ghost.Hide.Notice", lang)))

        entries.append(.header(id: 20, section: 2, text: wgString("Ghost.Behavior.Header", lang)))
        entries.append(wgToggle(21, 2, .ghostAutoOffline, "Ghost.AutoOffline", lang, enabled: master && settings.bool(.ghostNoOnline)))
        entries.append(wgToggle(22, 2, .ghostReadOnInteract, "Ghost.ReadOnInteract", lang, enabled: master && settings.bool(.ghostNoRead)))
        entries.append(wgToggle(23, 2, .ghostSendScheduled, "Ghost.SendScheduled", lang, enabled: master))
        entries.append(.notice(id: 24, section: 2, text: wgString("Ghost.SendScheduled.Notice", lang)))

        entries.append(.toggle(id: 30, section: 3, key: "warnOnStoriesOpen", title: wgString("Ghost.StoryWarn", lang), value: SGSimpleSettings.shared.warnOnStoriesOpen, enabled: true))

        entries.append(.header(id: 40, section: 4, text: wgString("Ghost.Exceptions.Header", lang)))
        var nextId = 41
        for peerId in settings.readExceptions {
            entries.append(.text(id: nextId, section: 4, key: "e:\(peerId)", text: settings.peerTitle(peerId)))
            nextId += 1
        }
        entries.append(.notice(id: 4000, section: 4, text: wgString("Ghost.Exceptions.Notice", lang)))
        return entries
    })
    presentImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    return controller
}

// MARK: - Сохранение

private func wgSavingController(context: AccountContext) -> ViewController {
    let refresh = WGRefresh()
    let arguments = WGArguments(setBool: { key, value in
        wgSetBool(key, value)
        refresh.trigger()
    })
    return wgListController(context: context, title: { wgString("Main.Saving", $0) }, refresh: refresh, arguments: arguments, entries: { presentationData in
        let lang = presentationData.strings.baseLanguageCode
        let settings = WGSettings.shared

        var entries: [WGEntry] = []
        entries.append(.header(id: 1, section: 0, text: wgString("Saving.Header", lang)))
        entries.append(wgToggle(2, 0, .saveDeleted, "Saving.Deleted", lang))
        entries.append(wgToggle(3, 0, .saveEdits, "Saving.Edits", lang))
        entries.append(.notice(id: 4, section: 0, text: wgString("Saving.Notice", lang)))

        entries.append(wgToggle(10, 1, .saveFromBots, "Saving.Bots", lang, enabled: settings.saveDeleted || settings.saveEdits))
        entries.append(.notice(id: 11, section: 1, text: wgString("Saving.Limits", lang)))
        return entries
    })
}

// MARK: - Реклама и ограничения

private func wgOtherController(context: AccountContext) -> ViewController {
    let refresh = WGRefresh()
    let arguments = WGArguments(setBool: { key, value in
        wgSetBool(key, value)
        refresh.trigger()
    })
    return wgListController(context: context, title: { wgString("Main.Other", $0) }, refresh: refresh, arguments: arguments, entries: { presentationData in
        let lang = presentationData.strings.baseLanguageCode

        var entries: [WGEntry] = []
        entries.append(.header(id: 1, section: 0, text: wgString("Other.Ads.Header", lang)))
        entries.append(wgToggle(2, 0, .noAds, "Other.NoAds", lang))
        entries.append(.notice(id: 3, section: 0, text: wgString("Other.NoAds.Notice", lang)))

        entries.append(.header(id: 10, section: 1, text: wgString("Other.Restrictions.Header", lang)))
        entries.append(wgToggle(11, 1, .bypassCopyProtection, "Other.CopyProtection", lang))
        entries.append(.notice(id: 12, section: 1, text: wgString("Other.CopyProtection.Notice", lang)))
        return entries
    })
}

// MARK: - Оформление

private let wgFontOptions: [(value: String, title: String)] = [
    ("", ""),
    ("rounded", "SF Rounded"),
    ("serif", "New York"),
    ("mono", "SF Mono"),
    ("Avenir Next", "Avenir Next"),
    ("Helvetica Neue", "Helvetica Neue"),
    ("Georgia", "Georgia"),
    ("Verdana", "Verdana"),
    ("Arial", "Arial"),
    ("Trebuchet MS", "Trebuchet MS"),
    ("Times New Roman", "Times New Roman"),
    ("Charter", "Charter"),
    ("Palatino", "Palatino"),
    ("Courier New", "Courier New"),
    ("Menlo", "Menlo"),
    ("Futura", "Futura"),
    ("Gill Sans", "Gill Sans"),
    ("Optima", "Optima"),
    ("Baskerville", "Baskerville"),
    ("Didot", "Didot"),
    ("American Typewriter", "American Typewriter"),
    ("Copperplate", "Copperplate"),
    ("Chalkboard SE", "Chalkboard SE"),
    ("Noteworthy", "Noteworthy"),
    ("Marker Felt", "Marker Felt"),
    ("Bradley Hand", "Bradley Hand"),
    ("Snell Roundhand", "Snell Roundhand")
]

private func wgAppearanceController(context: AccountContext) -> ViewController {
    let refresh = WGRefresh()
    var presentImpl: ((ViewController, Any?) -> Void)?

    let editString: (WGSettings.StringKey, String, Int) -> Void = { key, titleKey, limit in
        let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        let prompt = promptController(context: context, text: wgString(titleKey, lang), value: WGSettings.shared.string(key), placeholder: wgString("Appearance.Mark.Placeholder", lang), characterLimit: limit, apply: { value in
            WGSettings.shared.setString(key, value ?? "")
            refresh.trigger()
        })
        presentImpl?(prompt, nil)
    }

    let arguments = WGArguments(setBool: { key, value in
        wgSetBool(key, value)
        refresh.trigger()
    }, open: { key in
        switch key {
        case "deletedMark":
            editString(.deletedMark, "Appearance.DeletedMark", 24)
        case "editedMark":
            editString(.editedMark, "Appearance.EditedMark", 24)
        case "fakePhone":
            editString(.fakePhone, "Appearance.FakePhone", 32)
        case "fakeUsername":
            editString(.fakeUsername, "Appearance.FakeUsername", 32)
        case "fakeStars":
            editString(.fakeStars, "Appearance.FakeStars", 12)
        case "font":
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.baseLanguageCode
            let actionSheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = []
            for option in wgFontOptions {
                let title = option.value.isEmpty ? wgString("Appearance.Font.System", lang) : option.title
                items.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    WGSettings.shared.setString(.appFont, option.value)
                    refresh.trigger()
                }))
            }
            actionSheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                    })
                ])
            ])
            presentImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        default:
            break
        }
    })

    let controller = wgListController(context: context, title: { wgString("Main.Appearance", $0) }, refresh: refresh, arguments: arguments, entries: { presentationData in
        let lang = presentationData.strings.baseLanguageCode
        let settings = WGSettings.shared
        let defaultLabel = wgString("Appearance.Default", lang)
        let realLabel = wgString("Appearance.Fake.Real", lang)
        let value: (WGSettings.StringKey, String) -> String = { key, fallback in
            let current = settings.string(key)
            return current.isEmpty ? fallback : current
        }
        let fontValue = settings.string(.appFont)
        let fontTitle = wgFontOptions.first(where: { $0.value == fontValue && !fontValue.isEmpty })?.title ?? wgString("Appearance.Font.System", lang)

        var entries: [WGEntry] = []
        entries.append(.header(id: 1, section: 0, text: wgString("Appearance.Messages.Header", lang)))
        entries.append(.link(id: 2, section: 0, key: "deletedMark", title: wgString("Appearance.DeletedMark", lang), label: value(.deletedMark, wgString("Message.Deleted", lang)), icon: nil, color: 0))
        entries.append(.link(id: 3, section: 0, key: "editedMark", title: wgString("Appearance.EditedMark", lang), label: value(.editedMark, defaultLabel), icon: nil, color: 0))
        entries.append(.notice(id: 4, section: 0, text: wgString("Appearance.Mark.Notice", lang)))

        entries.append(wgToggle(10, 1, .translucentDeleted, "Appearance.TranslucentDeleted", lang))
        entries.append(wgToggle(11, 1, .noBubbleTail, "Appearance.NoTail", lang))
        entries.append(wgToggle(12, 1, .hideShareButton, "Appearance.HideShare", lang))
        entries.append(.notice(id: 13, section: 1, text: wgString("Appearance.Messages.Notice", lang)))

        entries.append(.header(id: 20, section: 2, text: wgString("Appearance.Font.Header", lang)))
        entries.append(.link(id: 21, section: 2, key: "font", title: wgString("Appearance.Font", lang), label: fontTitle, icon: nil, color: 0))
        entries.append(.notice(id: 22, section: 2, text: wgString("Appearance.Font.Notice", lang) + "\n\n" + wgString("Appearance.Icon.Notice", lang)))

        entries.append(.header(id: 30, section: 3, text: wgString("Appearance.Fake.Header", lang)))
        entries.append(.link(id: 31, section: 3, key: "fakePhone", title: wgString("Appearance.FakePhone", lang), label: value(.fakePhone, realLabel), icon: nil, color: 0))
        entries.append(.link(id: 32, section: 3, key: "fakeUsername", title: wgString("Appearance.FakeUsername", lang), label: value(.fakeUsername, realLabel), icon: nil, color: 0))
        entries.append(.link(id: 33, section: 3, key: "fakeStars", title: wgString("Appearance.FakeStars", lang), label: value(.fakeStars, realLabel), icon: nil, color: 0))
        entries.append(.notice(id: 34, section: 3, text: wgString("Appearance.Fake.Notice", lang)))
        return entries
    })
    presentImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    return controller
}

// MARK: - Фильтры

/// Подгружает список заблокированных, чтобы их сообщения можно было скрывать.
private final class WGBlockedLoader {
    private var blockedContext: BlockedPeersContext?
    private var disposable: Disposable?

    deinit {
        self.disposable?.dispose()
    }

    func load(account: Account, updated: @escaping () -> Void) {
        let blockedContext = BlockedPeersContext(account: account, subject: .blocked)
        self.blockedContext = blockedContext
        var remainingPages = 30
        self.disposable?.dispose()
        self.disposable = (blockedContext.state
        |> deliverOnMainQueue).start(next: { [weak blockedContext] state in
            updated()
            if state.canLoadMore && !state.isLoadingMore && remainingPages > 0 {
                remainingPages -= 1
                blockedContext?.loadMore()
            }
        })
    }
}

private func wgFiltersController(context: AccountContext) -> ViewController {
    let refresh = WGRefresh()
    let blockedLoader = WGBlockedLoader()
    var presentImpl: ((ViewController, Any?) -> Void)?

    let confirmDelete: (@escaping () -> Void) -> Void = { remove in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: wgString("Common.Delete", presentationData.strings.baseLanguageCode), color: .destructive, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    remove()
                    refresh.trigger()
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        presentImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }

    let arguments = WGArguments(setBool: { key, value in
        wgSetBool(key, value)
        if key == WGSettings.Key.hideBlocked.rawValue && value {
            blockedLoader.load(account: context.account, updated: {
                refresh.trigger()
            })
        }
        refresh.trigger()
    }, open: { key in
        if key == "add" {
            let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
            let prompt = promptController(context: context, text: wgString("Filters.Add.Title", lang), value: "", placeholder: wgString("Filters.Add.Placeholder", lang), characterLimit: 200, apply: { value in
                if let value, !value.isEmpty {
                    WGSettings.shared.addGlobalFilter(value)
                    refresh.trigger()
                }
            })
            presentImpl?(prompt, nil)
        } else if key.hasPrefix("g:") {
            guard let index = Int(key.dropFirst(2)) else {
                return
            }
            confirmDelete({
                var filters = WGSettings.shared.globalFilters
                if index < filters.count {
                    filters.remove(at: index)
                    WGSettings.shared.setGlobalFilters(filters)
                }
            })
        } else if key.hasPrefix("c:") {
            let parts = key.dropFirst(2).split(separator: ":")
            guard parts.count == 2, let peerId = Int64(parts[0]), let index = Int(parts[1]) else {
                return
            }
            confirmDelete({
                var filters = WGSettings.shared.chatFilters(peerId: peerId)
                if index < filters.count {
                    filters.remove(at: index)
                    WGSettings.shared.setChatFilters(filters, peerId: peerId)
                }
            })
        }
    })

    let controller = wgListController(context: context, title: { wgString("Main.Filters", $0) }, refresh: refresh, arguments: arguments, entries: { presentationData in
        let lang = presentationData.strings.baseLanguageCode
        let settings = WGSettings.shared

        var entries: [WGEntry] = []
        entries.append(wgToggle(1, 0, .filtersEnabled, "Filters.Enable", lang))
        entries.append(.notice(id: 2, section: 0, text: wgString("Filters.Enable.Notice", lang)))

        entries.append(.header(id: 10, section: 1, text: wgString("Filters.Global.Header", lang)))
        for (index, filter) in settings.globalFilters.enumerated() {
            entries.append(.text(id: 100 + index, section: 1, key: "g:\(index)", text: filter))
        }
        entries.append(.action(id: 5000, section: 1, key: "add", title: wgString("Filters.Add", lang), destructive: false))
        entries.append(.notice(id: 5001, section: 1, text: wgString("Filters.Add.Notice", lang)))

        let chatFilters = settings.chatFilters
        if !chatFilters.isEmpty {
            entries.append(.header(id: 6000, section: 2, text: wgString("Filters.Chats.Header", lang)))
            var nextId = 6001
            for peerId in chatFilters.keys.sorted() {
                let title = settings.peerTitle(peerId)
                for (index, filter) in (chatFilters[peerId] ?? []).enumerated() {
                    entries.append(.text(id: nextId, section: 2, key: "c:\(peerId):\(index)", text: "\(title): \(filter)"))
                    nextId += 1
                }
            }
        }

        entries.append(wgToggle(9000, 3, .hideBlocked, "Filters.Blocked", lang))
        entries.append(.notice(id: 9001, section: 3, text: wgString("Filters.Blocked.Notice", lang, "\(settings.blockedPeersCount)")))
        return entries
    })
    presentImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    if WGSettings.shared.hideBlocked {
        blockedLoader.load(account: context.account, updated: {
            refresh.trigger()
        })
    }
    return controller
}

// MARK: - Добавление фильтра из сообщения

public func wgPresentAddFilter(context: AccountContext, peerId: Int64, text: String, present: @escaping (ViewController, Any?) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let lang = presentationData.strings.baseLanguageCode

    var suggestion = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    if suggestion.count > 64 {
        suggestion = String(suggestion.prefix(64))
    }

    let askPattern: (Bool) -> Void = { onlyThisChat in
        let prompt = promptController(context: context, text: wgString("Filters.Add.Title", lang), value: suggestion, placeholder: wgString("Filters.Add.Placeholder", lang), characterLimit: 200, apply: { value in
            guard let value, !value.isEmpty else {
                return
            }
            if onlyThisChat {
                WGSettings.shared.addChatFilter(value, peerId: peerId)
            } else {
                WGSettings.shared.addGlobalFilter(value)
            }
            if !WGSettings.shared.bool(.filtersEnabled) {
                WGSettings.shared.set(.filtersEnabled, true)
            }
        })
        present(prompt, nil)
    }

    let actionSheet = ActionSheetController(presentationData: presentationData)
    actionSheet.setItemGroups([
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: wgString("Filters.Scope.Chat", lang), color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                askPattern(true)
            }),
            ActionSheetButtonItem(title: wgString("Filters.Scope.All", lang), color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                askPattern(false)
            })
        ]),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])
    ])
    present(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
}

// MARK: - История правок

public func wgEditHistoryController(context: AccountContext, currentText: String, edits: [WGMessageAttribute.Edit]) -> ViewController {
    let refresh = WGRefresh()

    return wgListController(context: context, title: { wgString("EditHistory.Title", $0) }, refresh: refresh, arguments: WGArguments(), entries: { presentationData in
        let lang = presentationData.strings.baseLanguageCode
        let emptyText = wgString("EditHistory.Empty", lang)

        var entries: [WGEntry] = []
        entries.append(.header(id: 1, section: 0, text: wgString("EditHistory.Current", lang)))
        entries.append(.text(id: 2, section: 0, key: "", text: currentText.isEmpty ? emptyText : currentText))

        var nextId = 10
        var section: Int32 = 1
        for edit in edits.reversed() {
            let date = stringForMediumDate(timestamp: edit.date, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat)
            entries.append(.header(id: nextId, section: section, text: wgString("EditHistory.Before", lang, date.uppercased())))
            entries.append(.text(id: nextId + 1, section: section, key: "", text: edit.text.isEmpty ? emptyText : edit.text))
            nextId += 2
            section += 1
        }
        return entries
    })
}
