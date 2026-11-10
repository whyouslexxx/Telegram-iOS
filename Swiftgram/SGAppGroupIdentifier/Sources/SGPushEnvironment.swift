import Foundation

/// The signing profile can change when the IPA is re-signed without recompiling.
/// Read its APNs environment rather than inferring it from compiler flags.
public func sgPushNotificationsUseSandbox(bundle: Bundle = .main) -> Bool {
    if let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
       let data = try? Data(contentsOf: url),
       let start = data.range(of: Data("<plist".utf8)),
       let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound ..< data.endIndex),
       let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound ..< end.upperBound), options: [], format: nil),
       let profile = plist as? [String: Any],
       let entitlements = profile["Entitlements"] as? [String: Any],
       let environment = entitlements["aps-environment"] as? String {
        switch environment {
        case "development":
            return true
        case "production":
            return false
        default:
            break
        }
    }
    // App Store packages have no embedded profile; preserve their release default.
    #if DEBUG
    return true
    #else
    return false
    #endif
}
