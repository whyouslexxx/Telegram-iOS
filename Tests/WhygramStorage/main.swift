import Foundation

func check(_ value: Bool, _ message: String) {
    precondition(value, message)
}

func word(_ value: UInt32, big: Bool) -> Data {
    var value = big ? value.bigEndian : value.littleEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}

func signedExecutable(_ entitlements: [String: Any]) throws -> Data {
    let payload = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
    let blob = word(0xfade7171, big: true) + word(UInt32(payload.count + 8), big: true) + payload
    let signature = word(0xfade0cc0, big: true) + word(UInt32(blob.count + 20), big: true)
        + word(1, big: true) + word(5, big: true) + word(20, big: true) + blob
    var header = Data(repeating: 0, count: 32)
    header.replaceSubrange(0 ..< 4, with: word(0xfeedfacf, big: false))
    header.replaceSubrange(16 ..< 20, with: word(1, big: false))
    header.replaceSubrange(20 ..< 24, with: word(16, big: false))
    return header + word(0x1d, big: false) + word(16, big: false)
        + word(48, big: false) + word(UInt32(signature.count), big: false) + signature
}

let entitlements: [String: Any] = [
    "aps-environment": "production",
    "com.apple.security.application-groups": ["group.signer.1", "group.signer.2"]
]
let executable = try signedExecutable(entitlements)
let parsed = sgEntitlementsInExecutable(executable)
check(parsed?["aps-environment"] as? String == "production", "Read signed APNs environment")
check(parsed?["com.apple.security.application-groups"] as? [String] == ["group.signer.1", "group.signer.2"], "Read signed groups")
for size in 0 ..< executable.count {
    check(sgEntitlementsInExecutable(Data(executable.prefix(size))) == nil, "Reject truncated signatures")
}
var corrupt = executable
corrupt.replaceSubrange(44 ..< 48, with: word(UInt32.max, big: false))
check(sgEntitlementsInExecutable(corrupt) == nil, "Reject out-of-bounds signature")
var badSlot = executable
badSlot.replaceSubrange(64 ..< 68, with: word(UInt32.max, big: true))
check(sgEntitlementsInExecutable(badSlot) == nil, "Reject out-of-bounds entitlement slot")

let files = FileManager.default
let temporary = files.temporaryDirectory.appendingPathComponent("whygram-tests-\(UUID().uuidString)")
try files.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? files.removeItem(at: temporary) }
let source = temporary.appendingPathComponent("private")
let database = source.appendingPathComponent("telegram-data")
try files.createDirectory(at: database, withIntermediateDirectories: true)
let key = Data((0 ..< 48).map { UInt8($0) })
let account = Data("existing account database".utf8)
try key.write(to: database.appendingPathComponent(".tempkey"))
try account.write(to: database.appendingPathComponent("db.sqlite"))
let destination = temporary.appendingPathComponent("group/whygram-shared/app.id")
try sgMigrateStandaloneStorage(from: source, to: destination)
check(try Data(contentsOf: destination.appendingPathComponent("telegram-data/.tempkey")) == key, "Preserve database encryption key")
check(try Data(contentsOf: destination.appendingPathComponent("telegram-data/db.sqlite")) == account, "Preserve account data")
check(files.fileExists(atPath: database.appendingPathComponent("db.sqlite").path), "Keep source backup")
let newer = Data("newer shared account data".utf8)
try newer.write(to: destination.appendingPathComponent("telegram-data/db.sqlite"))
try sgMigrateStandaloneStorage(from: source, to: destination)
check(try Data(contentsOf: destination.appendingPathComponent("telegram-data/db.sqlite")) == newer, "Never overwrite an existing shared store")
let conflict = temporary.appendingPathComponent("conflict")
try files.createDirectory(at: conflict, withIntermediateDirectories: true)
try account.write(to: conflict.appendingPathComponent("unrelated"))
do {
    try sgMigrateStandaloneStorage(from: source, to: conflict)
    preconditionFailure("Must reject nonempty destination without database")
} catch { }
check(try Data(contentsOf: conflict.appendingPathComponent("unrelated")) == account, "Preserve conflicting destination")
print("Whygram signing and storage checks passed")
