// MARK: Whygram
import Foundation
import Postbox

/// Локальная пометка Whygram на сообщении: когда собеседник его удалил и какие
/// версии текста были до правок. На сервер не отправляется.
public final class WGMessageAttribute: MessageAttribute {
    public struct Edit: Equatable {
        public let text: String
        public let date: Int32

        public init(text: String, date: Int32) {
            self.text = text
            self.date = date
        }
    }

    public static let maxEdits = 50

    public let deletedDate: Int32?
    public let edits: [Edit]

    public init(deletedDate: Int32?, edits: [Edit]) {
        self.deletedDate = deletedDate
        self.edits = edits
    }

    required public init(decoder: PostboxDecoder) {
        let deletedDate = decoder.decodeInt32ForKey("dd", orElse: 0)
        self.deletedDate = deletedDate == 0 ? nil : deletedDate
        let texts = decoder.decodeStringArrayForKey("et")
        let dates = decoder.decodeInt32ArrayForKey("ed")
        var edits: [Edit] = []
        for i in 0 ..< min(texts.count, dates.count) {
            edits.append(Edit(text: texts[i], date: dates[i]))
        }
        self.edits = edits
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.deletedDate ?? 0, forKey: "dd")
        encoder.encodeStringArray(self.edits.map { $0.text }, forKey: "et")
        encoder.encodeInt32Array(self.edits.map { $0.date }, forKey: "ed")
    }
}

public extension Message {
    var wgAttribute: WGMessageAttribute? {
        for attribute in self.attributes {
            if let attribute = attribute as? WGMessageAttribute {
                return attribute
            }
        }
        return nil
    }

    /// Сообщение удалено у собеседника, но сохранено локально.
    var wgIsDeleted: Bool {
        return self.wgAttribute?.deletedDate != nil
    }
}
