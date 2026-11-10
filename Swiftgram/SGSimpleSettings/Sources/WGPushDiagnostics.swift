import Foundation

/// Only registration results are stored, never device tokens, keys or payloads.
public enum WGPushDiagnostics {
    public static func record(_ event: String, status: String) {
        let entry: [String: Any] = ["status": status, "date": Date().timeIntervalSince1970]
        UserDefaults.standard.set(entry, forKey: "wg.push.diagnostics.\(event)")
    }

    public static func status(_ event: String) -> String {
        guard let entry = UserDefaults.standard.dictionary(forKey: "wg.push.diagnostics.\(event)"),
              let status = entry["status"] as? String,
              let date = entry["date"] as? Double else { return "Нет результата" }
        let formatted = DateFormatter.localizedString(from: Date(timeIntervalSince1970: date), dateStyle: .short, timeStyle: .medium)
        return "\(status)\n\(formatted)"
    }
}
