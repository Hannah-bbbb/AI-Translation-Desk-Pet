import Foundation

/// Moves preferences and API keys saved under an earlier bundle identifier to the current one,
/// for example after a fork renames the app:
///
///     build/译喵.app/Contents/MacOS/Yimiao --import-from com.example.old-name
///
/// Nothing already saved under the current identifier is overwritten. The keychain items
/// belong to the old identity, so macOS asks once before handing each key over.
@MainActor
enum Migration {
    static func importSettings(from old: String) -> String {
        let current = AppIdentity.bundleID
        guard old != current else { return "旧标识符和当前的相同，不需要导入。" }
        var imported: [String] = []

        let defaults = UserDefaults.standard
        if let saved = defaults.persistentDomain(forName: old), !saved.isEmpty {
            let existing = defaults.persistentDomain(forName: current) ?? [:]
            defaults.setPersistentDomain(saved.merging(existing) { _, kept in kept }, forName: current)
            imported.append("\(saved.count) 项设置")
        }
        for provider in AIProvider.allCases where Keychain.load(for: provider).isEmpty {
            let key = Keychain.load(for: provider, service: old)
            guard !key.isEmpty else { continue }
            Keychain.save(key, for: provider)
            imported.append("\(provider.name) API Key")
        }
        return imported.isEmpty ? "在 \(old) 下没有找到可导入的内容。" : "已从 \(old) 导入：\(imported.joined(separator: "、"))。"
    }
}
