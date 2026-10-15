import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case deepseek
    case kimi

    var id: String { rawValue }
    var name: String { self == .deepseek ? "DeepSeek" : "Kimi" }
    var defaultBaseURL: String {
        self == .deepseek ? "https://api.deepseek.com" : "https://api.moonshot.cn/v1"
    }
    var modelPresets: [String] {
        self == .deepseek ? ["deepseek-flash", "deepseek-v4-pro"] : ["kimi-k2.6", "kimi-k3"]
    }
    var keyURL: URL {
        URL(string: self == .deepseek
            ? "https://platform.deepseek.com/api_keys"
            : "https://platform.kimi.com/console/api-keys")!
    }
    var keychainAccount: String { "\(rawValue)-api-key" }
    var environmentKey: String { self == .deepseek ? "DEEPSEEK_API_KEY" : "MOONSHOT_API_KEY" }

    // Keep the existing DeepSeek preferences and keychain account intact.
    func preferenceKey(_ field: String) -> String {
        self == .deepseek ? field : "\(rawValue).\(field)"
    }

    static func forHost(_ host: String) -> AIProvider? {
        let host = host.lowercased()
        if host == "api.deepseek.com" { return .deepseek }
        if host == "api.moonshot.cn" || host == "api.moonshot.ai" { return .kimi }
        return nil
    }
}
