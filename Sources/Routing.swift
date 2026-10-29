import Foundation

struct Rule: Codable, Identifiable, Equatable {
    var id = UUID()
    var sourceID: String
    var sourceName: String
    var browserID: String
    var enabled = true
}

struct Preferences: Codable {
    static let currentVersion = 1
    var schemaVersion = currentVersion
    var defaultBrowserID = "com.apple.Safari"
    var askEveryTime = false
    var rules: [Rule] = []

    enum CodingKeys: String, CodingKey { case schemaVersion, defaultBrowserID, askEveryTime, rules }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        guard (0...Self.currentVersion).contains(version) else {
            throw ConfigurationError(message: "不支持的配置版本：\(version)")
        }
        schemaVersion = Self.currentVersion
        defaultBrowserID = try values.decodeIfPresent(String.self, forKey: .defaultBrowserID) ?? "com.apple.Safari"
        askEveryTime = try values.decodeIfPresent(Bool.self, forKey: .askEveryTime) ?? false
        rules = try values.decodeIfPresent([Rule].self, forKey: .rules) ?? []
    }

    func validate() throws {
        guard schemaVersion == Self.currentVersion else {
            throw ConfigurationError(message: "不支持的配置版本：\(schemaVersion)")
        }
        guard Set(rules.map(\.id)).count == rules.count,
              Set(rules.map(\.sourceID)).count == rules.count,
              rules.allSatisfy({ !$0.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ConfigurationError(message: "配置包含重复规则或空的来源应用。")
        }
    }
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

func routingExplanation(sourceID: String?, preferences: Preferences, forceChoice: Bool = false) -> String {
    if forceChoice { return "手动更换浏览器" }
    if preferences.askEveryTime { return "已开启每次询问，跳过自动规则" }
    if let rule = preferences.rules.first(where: { $0.enabled && $0.sourceID == sourceID }) {
        return "命中应用规则：\(rule.sourceName)"
    }
    return sourceID == nil ? "未识别到来源，使用默认浏览器" : "没有启用的匹配规则，使用默认浏览器"
}
