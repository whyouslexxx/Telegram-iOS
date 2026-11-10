import Foundation

public let FALLBACK_BASE_BUNDLE_ID: String = "app.swiftgram.ios"

public func sgBaseBundleIdentifier() -> String {
    let baseBundleId: String
    if let bundleId: String = Bundle.main.bundleIdentifier {
        if Bundle.main.bundlePath.hasSuffix(".appex") {
            if let lastDotRange: Range<String.Index> = bundleId.range(of: ".", options: [.backwards]) {
                baseBundleId = String(bundleId[..<lastDotRange.lowerBound])
            } else {
                baseBundleId = FALLBACK_BASE_BUNDLE_ID
            }
        } else {
            baseBundleId = bundleId
        }
    } else {
        baseBundleId = FALLBACK_BASE_BUNDLE_ID
    }
    return baseBundleId
}

public func sgAppGroupIdentifier() -> String {
    let result = sgSelectedAppGroupIdentifier
    
    #if DEBUG
    print("APP_GROUP_IDENTIFIER: \(result)")
    #endif
    
    return result
}

private let sgSelectedAppGroupIdentifier = sgResolvedAppGroupIdentifier()

/// Only the original, app-specific group uses Telegram's legacy layout.
/// Certificate-provider groups may be shared by unrelated signed apps.
public func sgAppGroupBaseURL() -> URL? {
    let group = sgAppGroupIdentifier()
    guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
    let base: URL
    if group == "group.\(sgBaseBundleIdentifier())" {
        base = container
    } else {
        base = container.appendingPathComponent("whygram-shared", isDirectory: true)
            .appendingPathComponent(sgBaseBundleIdentifier(), isDirectory: true)
    }
    if Bundle.main.bundleURL.pathExtension == "appex",
       !FileManager.default.fileExists(atPath: base.appendingPathComponent("telegram-data/.tempkey").path) {
        return nil
    }
    return base
}

/// Before any database is opened, publish a complete copy by an atomic rename.
/// Existing shared data always wins; the original private copy is retained.
public func sgMigrateStandaloneStorage(from source: URL, to destination: URL) throws {
    let files = FileManager.default
    guard files.fileExists(atPath: source.appendingPathComponent("telegram-data").path),
          !files.fileExists(atPath: destination.appendingPathComponent("telegram-data").path) else { return }
    // Never merge database files or encryption keys from two different stores.
    guard !files.fileExists(atPath: destination.path) else {
        throw CocoaError(.fileWriteFileExists)
    }
    let parent = destination.deletingLastPathComponent()
    try files.createDirectory(at: parent, withIntermediateDirectories: true, attributes: nil)
    let staging = parent.appendingPathComponent(".whygram-migration-\(UUID().uuidString)", isDirectory: true)
    defer { try? files.removeItem(at: staging) }
    try files.copyItem(at: source, to: staging)
    try files.moveItem(at: staging, to: destination)
}
