import Foundation

let selfID = "local.browserrouter.app"
let web = URL(string: "https://example.com/a?x=1#section")!
var preferences = Preferences()
func expect(_ actual: Route, _ expected: Route, _ name: String) {
    guard actual == expected else { fatalError("FAILED: \(name): \(actual)") }
    print("PASS: \(name)")
}
func resolve(_ source: String? = nil, _ url: URL = web) -> Route {
    route(url: url, sourceID: source, preferences: preferences, selfID: selfID)
}
expect(resolve(), .browser("com.apple.Safari"), "unknown sender uses default")
preferences.rules = [Rule(sourceID: "work.app", sourceName: "Work", browserID: "com.google.Chrome")]
expect(resolve("work.app"), .browser("com.google.Chrome"), "source application match")
expect(resolve("other.app"), .browser("com.apple.Safari"), "unmatched source falls back")
preferences.rules[0].enabled = false
expect(resolve("work.app"), .browser("com.apple.Safari"), "disabled rules ignored")
preferences.rules[0].enabled = true
preferences.askEveryTime = true
expect(resolve("work.app"), .ask, "manual choice overrides rules")
expect(resolve(nil, URL(string: "file:///tmp/example")!), .reject, "non-web schemes rejected")
expect(resolve(nil, URL(string: "https:")!), .reject, "missing host rejected")
preferences.askEveryTime = false
preferences.defaultBrowserID = selfID
expect(resolve(), .ask, "self routing cannot loop")
preferences.rules[0].browserID = selfID
expect(resolve("work.app"), .ask, "self-target rule cannot loop")
let data = try JSONEncoder().encode(preferences)
let decoded = try JSONDecoder().decode(Preferences.self, from: data)
assert(decoded.rules == preferences.rules && decoded.defaultBrowserID == preferences.defaultBrowserID)
print("PASS: preferences round trip")

func check(_ value: Bool, _ name: String) {
    guard value else { fatalError("FAILED: \(name)") }
    print("PASS: \(name)")
}
func expectError(_ name: String, _ action: () throws -> Void) {
    do { try action(); fatalError("FAILED: \(name) did not throw") }
    catch { print("PASS: \(name)") }
}

let root = FileManager.default.temporaryDirectory.appendingPathComponent("browserrouter-tests-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let configURL = root.appendingPathComponent("preferences.json")
let configuration = ConfigurationFile(url: configURL)
check(configuration.load().preferences.rules.isEmpty, "missing configuration starts clean")
let legacy = Data(#"{"defaultBrowserID":"com.google.Chrome","askEveryTime":true,"rules":[]}"#.utf8)
try legacy.write(to: configURL)
let migrated = configuration.load().preferences
check(migrated.schemaVersion == 1 && migrated.defaultBrowserID == "com.google.Chrome" && migrated.askEveryTime,
      "legacy configuration migrates without changing settings")
try configuration.save(migrated)
let saved = try Data(contentsOf: configURL)
check(String(decoding: saved, as: UTF8.self).contains("schemaVersion"), "saved configuration has schema version")
expectError("wrong field types are rejected") { _ = try configuration.decode(Data(#"{"rules":"broken"}"#.utf8)) }
var duplicates = Preferences()
let duplicate = Rule(sourceID: "example.sender", sourceName: "Example", browserID: "com.apple.Safari")
duplicates.rules = [duplicate, duplicate]
expectError("duplicate rule identities are rejected") { try configuration.save(duplicates) }

let corrupt = Data("not valid json".utf8)
try corrupt.write(to: configURL)
let recovered = ConfigurationFile(url: configURL)
let recovery = recovered.load()
check(recovery.notice != nil && recovered.writeBlock == nil, "corrupt configuration recovers only after backup")
let backupFiles = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasPrefix("preferences-backup-") }
let backupData = try Data(contentsOf: backupFiles[0])
check(backupFiles.count == 1 && backupData == corrupt, "backup preserves exact corrupt bytes")
try recovered.save(Preferences())
check(try recovered.decode(Data(contentsOf: configURL)).rules.isEmpty, "safe recovery can save new settings")

let invalidImport = root.appendingPathComponent("invalid-import.json")
try corrupt.write(to: invalidImport)
let beforeImport = try Data(contentsOf: configURL)
expectError("invalid import is rejected") { _ = try recovered.importPreferences(from: invalidImport) }
let afterImport = try Data(contentsOf: configURL)
check(beforeImport == afterImport, "invalid import leaves current file unchanged")
let validImport = root.appendingPathComponent("valid-import.json")
try legacy.write(to: validImport)
let imported = try recovered.importPreferences(from: validImport)
check(imported.defaultBrowserID == "com.google.Chrome", "valid import applies settings")
let importedBackups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasPrefix("preferences-backup-") }
check(importedBackups.count == 2, "import backs up the prior configuration")
let exportURL = root.appendingPathComponent("export.json")
try recovered.export(imported, to: exportURL)
check(try recovered.decode(Data(contentsOf: exportURL)).askEveryTime, "exported settings round trip")
expectError("export cannot overwrite active configuration") { try recovered.export(imported, to: configURL) }

let future = Data(#"{"schemaVersion":999,"rules":[]}"#.utf8)
try future.write(to: configURL)
let futureFile = ConfigurationFile(url: configURL)
_ = futureFile.load()
check(futureFile.writeBlock != nil, "future configuration versions are read-only")
expectError("future configuration cannot be overwritten") { try futureFile.save(Preferences()) }
expectError("import cannot bypass future version protection") { _ = try futureFile.importPreferences(from: validImport) }
check(try Data(contentsOf: configURL) == future, "future configuration bytes remain untouched")

final class BackupFailingManager: FileManager, @unchecked Sendable {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}
try corrupt.write(to: configURL)
let blocked = ConfigurationFile(url: configURL, manager: BackupFailingManager())
_ = blocked.load()
expectError("backup failure blocks saving") { try blocked.save(Preferences()) }
check(try Data(contentsOf: configURL) == corrupt, "backup failure preserves original bytes")

let queue = DeliveryQueue()
let first = LinkRequest(url: URL(string: "https://example.com/a?x=1&y=%E4%B8%AD#anchor")!, sourceID: "sender.app")
let second = LinkRequest(url: URL(string: "https://example.com/b")!, sourceID: nil)
queue.enqueue(first); queue.enqueue(second)
check(queue.next() == first && queue.next() == nil, "only one link is active during browser launch")
queue.fail(first.id, message: "launch failed")
check(queue.failures.first?.request.url.absoluteString == first.url.absoluteString, "failed launch preserves complete URL")
check(queue.next() == second, "later links continue after a failure")
queue.complete(first.id)
check(queue.active == second, "stale callback cannot finish a different link")
queue.complete(second.id)
queue.retry(first.id, chooseBrowser: true)
queue.retry(first.id, chooseBrowser: true)
check(queue.pending.count == 1, "repeated retry clicks do not duplicate delivery")
check(queue.next()?.forceChoice == true, "change browser overrides automatic routing")
queue.cancel(first.id)
check(queue.failures.count == 1, "cancelling browser choice retains failed link")
queue.retry(first.id, chooseBrowser: false)
check(queue.next()?.forceChoice == false, "retry uses current routing settings")
queue.complete(first.id)
check(queue.failures.isEmpty && queue.active == nil, "successful retry clears failure")
queue.enqueue(second); _ = queue.next(); queue.fail(second.id, message: "failed")
queue.retry(second.id, chooseBrowser: false); queue.dismiss(second.id)
check(queue.failures.isEmpty && queue.pending.isEmpty, "explicit dismissal removes failure and queued retry")
let diagnosticPreferences = Preferences()
check(routingExplanation(sourceID: nil, preferences: diagnosticPreferences).contains("未识别"), "unknown source diagnostic")
check(routingExplanation(sourceID: "example.sender", preferences: diagnosticPreferences).contains("没有启用"), "unmatched source diagnostic")
check(routingExplanation(sourceID: nil, preferences: diagnosticPreferences, forceChoice: true).contains("手动"), "manual recovery diagnostic")
