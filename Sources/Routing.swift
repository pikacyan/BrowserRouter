import Foundation

struct Rule: Codable, Identifiable, Equatable {
    var id = UUID()
    var sourceID: String
    var sourceName: String
    var browserID: String
    var enabled = true
}

struct Preferences: Codable {
    var defaultBrowserID = "com.apple.Safari"
    var askEveryTime = false
    var rules: [Rule] = []
}

enum Route: Equatable {
    case browser(String), ask, reject
}

func route(url: URL, sourceID: String?, preferences: Preferences, selfID: String) -> Route {
    guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
          let host = url.host, !host.isEmpty else { return .reject }
    if preferences.askEveryTime { return .ask }
    let target = preferences.rules.first { $0.enabled && $0.sourceID == sourceID }?.browserID
        ?? preferences.defaultBrowserID
    return target.isEmpty || target == selfID ? .ask : .browser(target)
}
