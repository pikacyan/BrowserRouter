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
