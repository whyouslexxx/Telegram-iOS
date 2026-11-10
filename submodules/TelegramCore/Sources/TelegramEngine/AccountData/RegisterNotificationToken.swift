import Foundation
import SwiftSignalKit
import Postbox
import SGSimpleSettings
internal import TelegramApi


public enum NotificationTokenType {
    case aps(encrypt: Bool)
    case voip
}

func _internal_unregisterNotificationToken(account: Account, token: Data, type: NotificationTokenType, otherAccountUserIds: [PeerId.Id]) -> Signal<Never, NoError> {
    let mappedType: Int32
    switch type {
        case .aps:
            mappedType = 1
        case .voip:
            mappedType = 9
    }
    return account.network.request(Api.functions.account.unregisterDevice(tokenType: mappedType, token: hexString(token), otherUids: otherAccountUserIds.map({ $0._internalGetInt64Value() })))
    |> retryRequest
    |> ignoreValues
}

func _internal_registerNotificationToken(account: Account, token: Data, type: NotificationTokenType, sandbox: Bool, otherAccountUserIds: [PeerId.Id], excludeMutedChats: Bool) -> Signal<Bool, NoError> {
    return masterNotificationsKey(account: account, ignoreDisabled: false)
    |> mapToSignal { masterKey -> Signal<Bool, NoError> in
        let mappedType: Int32
        var keyData = Data()
        switch type {
            case let .aps(encrypt):
                mappedType = 1
                if encrypt {
                    keyData = masterKey.data
                }
            case .voip:
                mappedType = 9
                keyData = masterKey.data
        }
        var flags: Int32 = 0
        if excludeMutedChats {
            flags |= 1 << 0
        }
        let diagnosticEvent = "telegram.\(mappedType).\(account.peerId.toInt64())"
        let environment = sandbox ? "sandbox" : "production"
        WGPushDiagnostics.record(diagnosticEvent, status: "Регистрация токена: \(environment)")
        return account.network.request(Api.functions.account.registerDevice(flags: flags, tokenType: mappedType, token: hexString(token), appSandbox: sandbox ? .boolTrue : .boolFalse, secret: Buffer(data: keyData), otherUids: otherAccountUserIds.map({ $0._internalGetInt64Value() })))
        |> map { result -> Bool in
            let accepted: Bool
            switch result {
            case .boolTrue: accepted = true
            case .boolFalse: accepted = false
            }
            WGPushDiagnostics.record(diagnosticEvent, status: accepted ? "Telegram принял токен (\(environment))" : "Telegram отклонил токен (\(environment))")
            return accepted
        }
        |> `catch` { error -> Signal<Bool, NoError> in
            WGPushDiagnostics.record(diagnosticEvent, status: "Ошибка Telegram: \(error.errorCode) \(error.errorDescription ?? "unknown")")
            if error.errorDescription == "TOKEN_WAS_INVALIDATED" {
                return .single(false)
            } else {
                return .single(true)
            }
        }
    }
}
