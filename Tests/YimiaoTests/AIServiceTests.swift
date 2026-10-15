import XCTest
@testable import Yimiao

final class AIServiceTests: XCTestCase {
    @MainActor
    func testSwitchPreservesLegacyConfigAndPendingKeysAcrossRelaunch() {
        let suite = "YimiaoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("https://legacy.example/v1", forKey: "baseURL")
        defaults.set("legacy-model", forKey: "model")
        defaults.set(true, forKey: "thinking")
        var keys: [AIProvider: String] = [.deepseek: "old-deepseek-key"]
        let settings = Settings(defaults: defaults, loadKey: { keys[$0] ?? "" },
                                storeKey: { keys[$1] = $0 }, environment: [:])
        XCTAssertEqual(settings.provider, .deepseek)
        XCTAssertEqual(settings.apiKey, "old-deepseek-key")
        XCTAssertEqual(settings.baseURL, "https://legacy.example/v1")
        XCTAssertEqual(settings.model, "legacy-model")
        XCTAssertTrue(settings.thinking)

        // Switch immediately, before the debounced keychain write can run.
        settings.apiKey = " new-deepseek-key \n"
        settings.provider = .kimi
        XCTAssertEqual(keys[.deepseek], "new-deepseek-key")
        XCTAssertEqual(settings.apiKey, "")
        XCTAssertEqual(settings.baseURL, "https://api.moonshot.cn/v1")
        XCTAssertEqual(settings.model, "kimi-k2.6")
        XCTAssertFalse(settings.thinking)
        settings.apiKey = "kimi-key"
        settings.baseURL = "https://api.moonshot.ai/v1"
        settings.model = "kimi-k3"
        settings.thinking = true
        settings.provider = .deepseek
        XCTAssertEqual(keys[.kimi], "kimi-key")
        XCTAssertEqual(settings.apiKey, "new-deepseek-key")
        XCTAssertEqual(settings.model, "legacy-model")
        XCTAssertEqual(settings.baseURL, "https://legacy.example/v1")
        XCTAssertTrue(settings.thinking)

        settings.provider = .kimi
        let restored = Settings(defaults: defaults, loadKey: { keys[$0] ?? "" },
                                storeKey: { keys[$1] = $0 }, environment: [:])
        XCTAssertEqual(restored.provider, .kimi)
        XCTAssertEqual(restored.apiKey, "kimi-key")
        XCTAssertEqual(restored.model, "kimi-k3")
        XCTAssertEqual(restored.baseURL, "https://api.moonshot.ai/v1")
        XCTAssertTrue(restored.thinking)
        XCTAssertEqual(restored.translatorConfig.service, .kimi)
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { ($0 as? String) == "kimi-key" })
        // Deleting one provider's key must not delete the other provider's key.
        restored.apiKey = ""
        restored.saveKeyNow()
        XCTAssertEqual(keys[.kimi], "")
        XCTAssertEqual(keys[.deepseek], "new-deepseek-key")
    }

    @MainActor
    func testEnvironmentFallbackIsProviderSpecific() {
        let suite = "YimiaoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults, loadKey: { _ in "" }, storeKey: { _, _ in
            XCTFail("Loading or switching providers must not write a key")
        }, environment: ["DEEPSEEK_API_KEY": "ds-env", "MOONSHOT_API_KEY": "kimi-env"])
        XCTAssertEqual(settings.apiKey, "ds-env")
        settings.provider = .kimi
        XCTAssertEqual(settings.apiKey, "kimi-env")
        settings.saveKeyNow()
    }

    func testKimiRequestURLAndModelSpecificParameters() throws {
        var config = TranslatorConfig(baseURL: " https://api.moonshot.cn/v1/ ", apiKey: " kimi-test-key\n",
                                      model: " kimi-k2.6 ", thinking: false, service: .kimi)
        let request = try Translator.makeRequest(system: "Translate", user: "Hello", stream: true,
                                                 thinking: false, config: config)
        XCTAssertEqual(request.url?.absoluteString, "https://api.moonshot.cn/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer kimi-test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        let instant = try body(request)
        XCTAssertEqual(instant["model"] as? String, "kimi-k2.6")
        XCTAssertEqual((instant["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertNil(instant["temperature"])
        let thinking = try payload(config, thinking: true)
        XCTAssertEqual((thinking["thinking"] as? [String: String])?["type"], "enabled")
        config.model = "kimi-k3"
        for enabled in [false, true] {
            let k3 = try payload(config, thinking: enabled)
            XCTAssertEqual(k3["reasoning_effort"] as? String, enabled ? "high" : "low")
            XCTAssertNil(k3["thinking"])
            XCTAssertNil(k3["temperature"])
        }
        config.model = "kimi-k2.7-code"
        XCTAssertFalse(config.supportsThinkingControl)
        XCTAssertNil(try payload(config, thinking: false)["thinking"])
    }

    func testCompanionRequestCanDisableKimiThinking() throws {
        let config = TranslatorConfig(baseURL: AIProvider.kimi.defaultBaseURL, apiKey: "test-key",
                                      model: "kimi-k2.6", thinking: true, service: .kimi)
        let request = try Translator.makeRequest(system: "Be a cat", user: "Say hello", stream: false,
                                                 thinking: false, config: config)
        let result = try body(request)
        XCTAssertEqual(result["stream"] as? Bool, false)
        XCTAssertEqual((result["thinking"] as? [String: String])?["type"], "disabled")
    }

    func testDeepSeekAndGenericEndpointsRemainCompatible() throws {
        var config = TranslatorConfig(baseURL: AIProvider.deepseek.defaultBaseURL, apiKey: "test-key",
                                      model: "deepseek-flash", thinking: false)
        let ds = try payload(config, thinking: false)
        XCTAssertEqual(ds["temperature"] as? Double, 1.3)
        XCTAssertEqual((ds["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertNil(try payload(config, thinking: true)["temperature"])
        config.baseURL = "http://localhost:1234/v1"
        let generic = try payload(config, thinking: true)
        XCTAssertNil(generic["thinking"])
        XCTAssertNil(generic["temperature"])
        XCTAssertEqual(config.provider, "localhost")
        XCTAssertNil(config.statusPage)
        config.baseURL = "https://api.moonshot.ai/v1"
        config.model = "kimi-k2.6"
        XCTAssertEqual(config.provider, "Kimi")
        XCTAssertEqual((try payload(config, thinking: false)["thinking"] as? [String: String])?["type"], "disabled")
    }

    func testInvalidCredentialsAndURLFailBeforeNetworking() {
        var config = TranslatorConfig(baseURL: "https://api.moonshot.cn/v1", apiKey: " \n",
                                      model: "kimi-k2.6", thinking: false, service: .kimi)
        XCTAssertThrowsError(try payload(config, thinking: false)) {
            guard case TranslatorError.missingKey = $0 else { return XCTFail("Expected missingKey") }
        }
        config.apiKey = "test-key"
        for invalid in ["", "ftp://example.com/v1", "https://example.com/v1?query=1"] {
            config.baseURL = invalid
            XCTAssertThrowsError(try payload(config, thinking: false)) {
                guard case TranslatorError.badURL = $0 else { return XCTFail("Expected badURL") }
            }
        }
    }

    private func payload(_ config: TranslatorConfig, thinking: Bool) throws -> [String: Any] {
        try body(Translator.makeRequest(system: "Translate", user: "Hello", stream: true,
                                        thinking: thinking, config: config))
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }
}
