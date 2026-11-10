import Foundation

/// The signing profile can change when the IPA is re-signed without recompiling.
/// Read its APNs environment rather than inferring it from compiler flags.
public func sgPushNotificationsUseSandbox(bundle: Bundle = .main) -> Bool {
    if let environment = sgExecutableEntitlements(bundle)["aps-environment"] as? String {
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
