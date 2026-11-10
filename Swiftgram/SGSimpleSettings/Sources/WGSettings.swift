// MARK: Whygram
import Foundation

/// Настройки Whygram. Значения кэшируются в памяти: к ним обращаются из горячих мест
/// (отрисовка сообщений, сетевые запросы), поэтому чтение не должно ходить в UserDefaults.
public final class WGSettings {
    public static let shared = WGSettings()

    public enum Key: String, CaseIterable {
        // Режим призрака
        case ghostMode
        case ghostNoRead
        case ghostNoStoryViews
        case ghostNoOnline
        case ghostNoTyping
        case ghostAutoOffline
        case ghostReadOnInteract
        case ghostSendScheduled
        // Сохранение
        case saveDeleted
        case saveEdits
        case saveFromBots
        // Фильтры
        case filtersEnabled
        case hideBlocked
        // Прочее
        case noAds
        case bypassCopyProtection
    }

    private static let enabledByDefault: Set<Key> = [
        .ghostNoRead,
        .ghostNoStoryViews,
        .ghostNoOnline,
        .ghostNoTyping,
        .ghostAutoOffline,
        .ghostReadOnInteract,
        .saveDeleted,
        .saveEdits,
        .filtersEnabled,
        .noAds
    ]

    private static let prefix = "wg_"
    private static let globalFiltersKey = "wg_globalFilters"
    private static let chatFiltersKey = "wg_chatFilters"
    private static let blockedPeerIdsKey = "wg_blockedPeerIds"

    private let defaults = UserDefaults.standard
    private let lock = NSLock()

    private var boolValues: [Key: Bool] = [:]
    private var globalFiltersValue: [String] = []
    private var chatFiltersValue: [String: [String]] = [:]
    private var blockedPeerIdsValue: Set<Int64> = []
    private var matcherCache: [String: WGFilterMatcher] = [:]

    private init() {
        for key in Key.allCases {
            let storageKey = WGSettings.prefix + key.rawValue
            if let value = self.defaults.object(forKey: storageKey) as? Bool {
                self.boolValues[key] = value
            } else {
                self.boolValues[key] = WGSettings.enabledByDefault.contains(key)
            }
        }
        self.globalFiltersValue = (self.defaults.array(forKey: WGSettings.globalFiltersKey) as? [String]) ?? []
        self.chatFiltersValue = (self.defaults.dictionary(forKey: WGSettings.chatFiltersKey) as? [String: [String]]) ?? [:]
        if let stored = self.defaults.array(forKey: WGSettings.blockedPeerIdsKey) as? [NSNumber] {
            self.blockedPeerIdsValue = Set(stored.map { $0.int64Value })
        }
    }

    // MARK: Переключатели

    public func bool(_ key: Key) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.boolValues[key] ?? false
    }

    public func set(_ key: Key, _ value: Bool) {
        self.lock.lock()
        self.boolValues[key] = value
        self.lock.unlock()
        self.defaults.set(value, forKey: WGSettings.prefix + key.rawValue)
    }

    private func ghost(_ key: Key) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return (self.boolValues[.ghostMode] ?? false) && (self.boolValues[key] ?? false)
    }

    public var ghostNoRead: Bool { return self.ghost(.ghostNoRead) }
    public var ghostNoStoryViews: Bool { return self.ghost(.ghostNoStoryViews) }
    public var ghostNoOnline: Bool { return self.ghost(.ghostNoOnline) }
    public var ghostNoTyping: Bool { return self.ghost(.ghostNoTyping) }
    public var ghostAutoOffline: Bool { return self.ghost(.ghostAutoOffline) }
    public var ghostSendScheduled: Bool { return self.ghost(.ghostSendScheduled) }
    public var ghostReadOnInteract: Bool {
        return self.ghost(.ghostNoRead) && self.bool(.ghostReadOnInteract)
    }

    public var saveDeleted: Bool { return self.bool(.saveDeleted) }
    public var saveEdits: Bool { return self.bool(.saveEdits) }
    public var saveFromBots: Bool { return self.bool(.saveFromBots) }
    public var noAds: Bool { return self.bool(.noAds) }
    public var bypassCopyProtection: Bool { return self.bool(.bypassCopyProtection) }

    // MARK: Фильтры

    public var globalFilters: [String] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.globalFiltersValue
    }

    public func setGlobalFilters(_ filters: [String]) {
        let cleaned = WGSettings.cleanedFilters(filters)
        self.lock.lock()
        self.globalFiltersValue = cleaned
        self.matcherCache.removeAll()
        self.lock.unlock()
        self.defaults.set(cleaned, forKey: WGSettings.globalFiltersKey)
    }

    public var chatFilters: [Int64: [String]] {
        self.lock.lock()
        defer { self.lock.unlock() }
        var result: [Int64: [String]] = [:]
        for (key, value) in self.chatFiltersValue {
            if let peerId = Int64(key) {
                result[peerId] = value
            }
        }
        return result
    }

    public func chatFilters(peerId: Int64) -> [String] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.chatFiltersValue["\(peerId)"] ?? []
    }

    public func setChatFilters(_ filters: [String], peerId: Int64) {
        let cleaned = WGSettings.cleanedFilters(filters)
        self.lock.lock()
        if cleaned.isEmpty {
            self.chatFiltersValue.removeValue(forKey: "\(peerId)")
        } else {
            self.chatFiltersValue["\(peerId)"] = cleaned
        }
        self.matcherCache.removeAll()
        let snapshot = self.chatFiltersValue
        self.lock.unlock()
        self.defaults.set(snapshot, forKey: WGSettings.chatFiltersKey)
    }

    public func addGlobalFilter(_ filter: String) {
        self.setGlobalFilters(self.globalFilters + [filter])
    }

    public func addChatFilter(_ filter: String, peerId: Int64) {
        self.setChatFilters(self.chatFilters(peerId: peerId) + [filter], peerId: peerId)
    }

    private static func cleanedFilters(_ filters: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for filter in filters {
            let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || seen.contains(trimmed) {
                continue
            }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    /// Нужно ли скрыть сообщение с таким текстом в этом чате.
    public func textMatchesFilters(_ text: String, peerId: Int64) -> Bool {
        if text.isEmpty {
            return false
        }
        self.lock.lock()
        guard self.boolValues[.filtersEnabled] ?? false else {
            self.lock.unlock()
            return false
        }
        let patterns = self.globalFiltersValue + (self.chatFiltersValue["\(peerId)"] ?? [])
        if patterns.isEmpty {
            self.lock.unlock()
            return false
        }
        var matchers: [WGFilterMatcher] = []
        matchers.reserveCapacity(patterns.count)
        for pattern in patterns {
            if let cached = self.matcherCache[pattern] {
                matchers.append(cached)
            } else {
                let matcher = WGFilterMatcher(pattern: pattern)
                self.matcherCache[pattern] = matcher
                matchers.append(matcher)
            }
        }
        self.lock.unlock()

        for matcher in matchers {
            if matcher.matches(text) {
                return true
            }
        }
        return false
    }

    // MARK: Заблокированные пользователи

    public var hideBlocked: Bool {
        return self.bool(.hideBlocked)
    }

    public func isPeerBlocked(_ peerId: Int64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.blockedPeerIdsValue.contains(peerId)
    }

    public func setPeerBlocked(_ peerId: Int64, isBlocked: Bool) {
        self.lock.lock()
        if isBlocked {
            self.blockedPeerIdsValue.insert(peerId)
        } else {
            self.blockedPeerIdsValue.remove(peerId)
        }
        let snapshot = self.blockedPeerIdsValue
        self.lock.unlock()
        self.defaults.set(snapshot.map { NSNumber(value: $0) }, forKey: WGSettings.blockedPeerIdsKey)
    }

    public func addBlockedPeers(_ peerIds: [Int64]) {
        if peerIds.isEmpty {
            return
        }
        self.lock.lock()
        let previousCount = self.blockedPeerIdsValue.count
        self.blockedPeerIdsValue.formUnion(peerIds)
        let snapshot = self.blockedPeerIdsValue
        self.lock.unlock()
        if snapshot.count != previousCount {
            self.defaults.set(snapshot.map { NSNumber(value: $0) }, forKey: WGSettings.blockedPeerIdsKey)
        }
    }

    public var blockedPeersCount: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.blockedPeerIdsValue.count
    }
}

/// Один фильтр. Обычная строка ищется как подстрока без учёта регистра;
/// строка с префиксом `re:` — регулярное выражение.
final class WGFilterMatcher {
    private let plain: String?
    private let regex: NSRegularExpression?

    init(pattern: String) {
        if pattern.hasPrefix("re:") {
            let expression = String(pattern.dropFirst(3))
            let compiled = try? NSRegularExpression(pattern: expression, options: [.caseInsensitive])
            self.regex = compiled
            self.plain = compiled == nil ? expression.lowercased() : nil
        } else {
            self.regex = nil
            self.plain = pattern.lowercased()
        }
    }

    func matches(_ text: String) -> Bool {
        if let regex = self.regex {
            let range = NSRange(text.startIndex ..< text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        } else if let plain = self.plain, !plain.isEmpty {
            return text.lowercased().contains(plain)
        } else {
            return false
        }
    }
}
