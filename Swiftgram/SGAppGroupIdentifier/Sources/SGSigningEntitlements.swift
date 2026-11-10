import Foundation

// Read the executable's actual signature. Re-signers may leave the original
// embedded.mobileprovision in extensions, so that file is not authoritative.
public func sgEntitlementsInExecutable(_ data: Data) -> [String: Any]? {
    func u32(_ offset: Int, bigEndian: Bool = false) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        let bytes = Array(data[offset ..< offset + 4])
        if bigEndian { return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } }
        return bytes.reversed().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
    guard u32(0) == 0xfeedfacf, let count = u32(16), let commandsSize = u32(20),
          data.count >= 32, Int(commandsSize) <= data.count - 32 else { return nil }
    let commandsEnd = 32 + Int(commandsSize)
    var offset = 32
    for _ in 0 ..< Int(count) {
        guard offset <= commandsEnd - 8, let command = u32(offset),
              let size = u32(offset + 4), size >= 8, Int(size) <= commandsEnd - offset else { return nil }
        if command == 0x1d {
            guard size >= 16, let start = u32(offset + 8), let length = u32(offset + 12),
                  Int(start) <= data.count, length >= 12, Int(length) <= data.count - Int(start) else { return nil }
            let base = Int(start)
            guard u32(base, bigEndian: true) == 0xfade0cc0,
                  let blobLength = u32(base + 4, bigEndian: true), blobLength >= 12, blobLength <= length,
                  let slots = u32(base + 8, bigEndian: true), slots <= (blobLength - 12) / 8 else { return nil }
            for index in 0 ..< Int(slots) {
                guard let relative = u32(base + 16 + index * 8, bigEndian: true),
                      relative <= blobLength - 8 else { return nil }
                let blob = base + Int(relative)
                guard let payloadLength = u32(blob + 4, bigEndian: true), payloadLength >= 8,
                      payloadLength <= blobLength - relative else { return nil }
                if u32(blob, bigEndian: true) == 0xfade7171 {
                    let payload = data.subdata(in: blob + 8 ..< blob + Int(payloadLength))
                    return (try? PropertyListSerialization.propertyList(from: payload, options: [], format: nil)) as? [String: Any]
                }
            }
            return nil
        }
        offset += Int(size)
    }
    return nil
}

func sgExecutableEntitlements(_ bundle: Bundle) -> [String: Any] {
    guard let url = bundle.executableURL, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [:] }
    return sgEntitlementsInExecutable(data) ?? [:]
}

func sgContainingAppBundle() -> Bundle {
    if Bundle.main.bundleURL.pathExtension == "appex",
       let bundle = Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()) {
        return bundle
    }
    return .main
}

private let sgMainSigningEntitlements = sgExecutableEntitlements(sgContainingAppBundle())

func sgSignedMainEntitlements() -> [String: Any] {
    return sgMainSigningEntitlements
}

/// Select the same authorized group in the main app and the notification service.
/// The private database lives in a bundle-specific subfolder of borrowed groups.
func sgResolvedAppGroupIdentifier() -> String {
    let expected = "group.\(sgBaseBundleIdentifier())"
    var groups = Set(sgSignedMainEntitlements()["com.apple.security.application-groups"] as? [String] ?? [])
    let plugins = sgContainingAppBundle().bundleURL.appendingPathComponent("PlugIns")
    if let urls = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil) {
        for url in urls where url.pathExtension == "appex" {
            guard let bundle = Bundle(url: url),
                  let ext = bundle.infoDictionary?["NSExtension"] as? [String: Any],
                  ext["NSExtensionPointIdentifier"] as? String == "com.apple.usernotifications.service" else { continue }
            let extensionGroups = sgExecutableEntitlements(bundle)["com.apple.security.application-groups"] as? [String] ?? []
            groups.formIntersection(extensionGroups)
        }
    }
    let candidates = groups.contains(expected) ? [expected] + groups.sorted().filter { $0 != expected } : groups.sorted()
    for group in candidates where group.hasPrefix("group.") {
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil {
            return group
        }
    }
    return expected
}
