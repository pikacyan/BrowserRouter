import Foundation

struct ConfigurationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ConfigurationLoad {
    var preferences: Preferences
    var notice: String?
}

/// Owns disk access so a failed read can never silently overwrite the original.
final class ConfigurationFile {
    let url: URL
    private(set) var writeBlock: String?
    private let manager: FileManager

    init(url: URL, manager: FileManager = .default) {
        self.url = url
        self.manager = manager
    }

    func load() -> ConfigurationLoad {
        guard manager.fileExists(atPath: url.path) else {
            return ConfigurationLoad(preferences: Preferences())
        }
        do {
            return ConfigurationLoad(preferences: try decode(Data(contentsOf: url)))
        } catch {
            let reason = error.localizedDescription
            // Never replace a file written by a newer app, even when a backup succeeds.
            let isFutureVersion = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url)))
                .flatMap { $0 as? [String: Any] }
                .flatMap { $0["schemaVersion"] as? Int }
                .map { $0 > Preferences.currentVersion } ?? false
            do {
                let backupURL = try backup()
                if isFutureVersion { writeBlock = "配置来自更新版本，请升级应用后再修改设置。" }
                return ConfigurationLoad(preferences: Preferences(), notice:
                    "配置未能读取：\(reason)\n原文件已备份为 \(backupURL.lastPathComponent)。"
                    + (isFutureVersion ? " 当前禁止覆盖原配置。" : " 当前使用默认设置。"))
            } catch {
                writeBlock = "无法备份原配置，已禁止保存以保护文件：\(error.localizedDescription)"
                return ConfigurationLoad(preferences: Preferences(), notice: "配置未能读取：\(reason)\n\(writeBlock!)")
            }
        }
    }

    func decode(_ data: Data) throws -> Preferences {
        let preferences = try JSONDecoder().decode(Preferences.self, from: data)
        try preferences.validate()
        return preferences
    }

    func encoded(_ preferences: Preferences) throws -> Data {
        try preferences.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(preferences)
    }

    func save(_ preferences: Preferences) throws {
        if let writeBlock { throw ConfigurationError(message: writeBlock) }
        let data = try encoded(preferences)
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Validate first, then preserve the current file before changing any disk or UI state.
    func importPreferences(from source: URL) throws -> Preferences {
        if let writeBlock { throw ConfigurationError(message: writeBlock) }
        let preferences = try decode(Data(contentsOf: source))
        if manager.fileExists(atPath: url.path) { _ = try backup() }
        try save(preferences)
        return preferences
    }

    func export(_ preferences: Preferences, to destination: URL) throws {
        guard destination.resolvingSymlinksInPath().standardizedFileURL != url.resolvingSymlinksInPath().standardizedFileURL else {
            throw ConfigurationError(message: "请选择其他文件名，不能用导出覆盖当前配置。")
        }
        try encoded(preferences).write(to: destination, options: .atomic)
    }

    @discardableResult
    private func backup() throws -> URL {
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent("preferences-backup-\(UUID().uuidString).json")
        try manager.copyItem(at: url, to: destination)
        return destination
    }
}
