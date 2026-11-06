import Combine
import Foundation

/// User preferences. Everything but the API key is stored in UserDefaults.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    @Published var provider: AIProvider {
        willSet { if newValue != provider { saveKeyNow() } }
        didSet {
            guard provider != oldValue else { return }
            defaults.set(provider.rawValue, forKey: "aiProvider")
            loadProvider()
        }
    }

    @Published var apiKey: String {
        didSet { if !loadingProvider { scheduleKeySave() } }
    }
    @Published var baseURL: String {
        didSet { if !loadingProvider { defaults.set(baseURL, forKey: provider.preferenceKey("baseURL")) } }
    }
    @Published var model: String {
        didSet { if !loadingProvider { defaults.set(model, forKey: provider.preferenceKey("model")) } }
    }
    /// Per-service thinking preference; the request adapts it to the selected model.
    @Published var thinking: Bool {
        didSet { if !loadingProvider { defaults.set(thinking, forKey: provider.preferenceKey("thinking")) } }
    }
    /// The language foreign text is translated into.
    @Published var primary: Language {
        didSet { defaults.set(primary.rawValue, forKey: "primary") }
    }
    /// The language text already in `primary` is translated into.
    @Published var secondary: Language {
        didSet { defaults.set(secondary.rawValue, forKey: "secondary") }
    }
    @Published var translatesPrimary: Bool {
        didSet { defaults.set(translatesPrimary, forKey: "translatesPrimary") }
    }
    /// Translate every selection, or only those made while holding ⌥.
    @Published var trigger: TranslationTrigger {
        didSet { defaults.set(trigger.rawValue, forKey: "translationTrigger") }
    }
    /// Whether to press ⌘C in apps that hide their selection from Accessibility.
    @Published var clipboardFallback: Bool {
        didSet { defaults.set(clipboardFallback, forKey: "clipboardFallback") }
    }
    /// Minutes without input before he dozes off; 0 means never.
    @Published var autoSleepMinutes: Int {
        didSet { defaults.set(autoSleepMinutes, forKey: "autoSleepMinutes") }
    }
    @Published var petScale: Double {
        didSet { defaults.set(petScale, forKey: "petScale") }
    }
    /// Whether he hops over to the text you selected to deliver the translation there.
    @Published var visitsSelection: Bool {
        didSet { defaults.set(visitsSelection, forKey: "visitsSelection") }
    }

    @Published var species: Species {
        didSet { defaults.set(species.rawValue, forKey: "species") }
    }
    @Published var coat: Coat {
        didSet { defaults.set(coat.rawValue, forKey: "coat") }
    }
    @Published var snakeSkin: SnakeSkin {
        didSet { defaults.set(snakeSkin.rawValue, forKey: "snakeSkin") }
    }
    @Published var dragonSkin: DragonSkin {
        didSet { defaults.set(dragonSkin.rawValue, forKey: "dragonSkin") }
    }
    @Published var outfit: OutfitChoice {
        didSet { defaults.set(outfit.rawValue, forKey: "outfit") }
    }
    /// Stalking and pouncing on a cursor waved in front of him.
    @Published var playsWithCursor: Bool {
        didSet { defaults.set(playsWithCursor, forKey: "playsWithCursor") }
    }
    @Published var reactsToTyping: Bool {
        didSet { defaults.set(reactsToTyping, forKey: "reactsToTyping") }
    }
    @Published var dancesToMusic: Bool {
        didSet { defaults.set(dancesToMusic, forKey: "dancesToMusic") }
    }
    @Published var reactsToBattery: Bool {
        didSet { defaults.set(reactsToBattery, forKey: "reactsToBattery") }
    }
    /// Now and then he hops up and sits on top of the window you are working in.
    @Published var sitsOnWindows: Bool {
        didSet { defaults.set(sitsOnWindows, forKey: "sitsOnWindows") }
    }

    /// Whether he ducks to the screen edge while a video is playing.
    @Published var hidesForVideo: Bool {
        didSet { defaults.set(hidesForVideo, forKey: "hidesForVideo") }
    }

    /// Master switch for everything he says without being asked.
    @Published var speaksUp: Bool {
        didSet { defaults.set(speaksUp, forKey: "speaksUp") }
    }
    @Published var greets: Bool {
        didSet { defaults.set(greets, forKey: "greets") }
    }
    /// Minutes of unbroken work before he suggests a break; 0 means never.
    @Published var breakMinutes: Int {
        didSet { defaults.set(breakMinutes, forKey: "breakMinutes") }
    }
    @Published var remindsOffWork: Bool {
        didSet { defaults.set(remindsOffWork, forKey: "remindsOffWork") }
    }
    /// Minutes after midnight.
    @Published var offWorkMinute: Int {
        didSet { defaults.set(offWorkMinute, forKey: "offWorkMinute") }
    }
    @Published var remindsBedtime: Bool {
        didSet { defaults.set(remindsBedtime, forKey: "remindsBedtime") }
    }
    @Published var bedtimeMinute: Int {
        didSet { defaults.set(bedtimeMinute, forKey: "bedtimeMinute") }
    }
    /// Whether the model writes his remarks. Off, or without a key, he uses his stock lines.
    @Published var writesOwnLines: Bool {
        didSet { defaults.set(writesOwnLines, forKey: "writesOwnLines") }
    }
    /// Whether looked-up words go into the vocabulary list.
    @Published var keepsVocabulary: Bool {
        didSet { defaults.set(keepsVocabulary, forKey: "keepsVocabulary") }
    }
    @Published var quizzes: Bool {
        didSet { defaults.set(quizzes, forKey: "quizzes") }
    }
    /// Adds today's tally to the end-of-day reminder.
    @Published var dailySummary: Bool {
        didSet { defaults.set(dailySummary, forKey: "dailySummary") }
    }

    private let defaults: UserDefaults
    private let loadKey: (AIProvider) -> String
    private let storeKey: (String, AIProvider) -> Void
    private let environment: [String: String]
    private var loadingProvider = false
    private var keySave: Task<Void, Never>?

    init(defaults: UserDefaults = .standard,
         loadKey: @escaping (AIProvider) -> String = { Keychain.load(for: $0) },
         storeKey: @escaping (String, AIProvider) -> Void = { Keychain.save($0, for: $1) },
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.defaults = defaults
        self.loadKey = loadKey
        self.storeKey = storeKey
        self.environment = environment
        defaults.register(defaults: [
            "baseURL": AIProvider.deepseek.defaultBaseURL,
            "model": AIProvider.deepseek.modelPresets[0],
            "primary": Language.chineseSimplified.rawValue,
            "secondary": Language.english.rawValue,
            "translatesPrimary": true,
            "translationTrigger": TranslationTrigger.automatic.rawValue,
            "clipboardFallback": true,
            "autoSleepMinutes": 5,
            "petScale": 1.0,
            "visitsSelection": true,
            "species": Species.cat.rawValue,
            "coat": Coat.orange.rawValue,
            "snakeSkin": SnakeSkin.mint.rawValue,
            "dragonSkin": DragonSkin.red.rawValue,
            "outfit": OutfitChoice.festival.rawValue,
            "playsWithCursor": true,
            "reactsToTyping": true,
            "dancesToMusic": true,
            "reactsToBattery": true,
            "sitsOnWindows": true,
            "hidesForVideo": true,
            "speaksUp": true,
            "greets": true,
            "breakMinutes": 50,
            "remindsOffWork": true,
            "offWorkMinute": 18 * 60 + 30,
            "remindsBedtime": true,
            "bedtimeMinute": 23 * 60 + 30,
            "writesOwnLines": true,
            "keepsVocabulary": true,
            "quizzes": true,
            "dailySummary": true,
        ])
        // When launched from a terminal with no key saved yet, the conventional variable works too.
        let selected = AIProvider(rawValue: defaults.string(forKey: "aiProvider") ?? "") ?? .deepseek
        provider = selected
        let saved = loadKey(selected)
        apiKey = saved.isEmpty ? environment[selected.environmentKey] ?? "" : saved
        baseURL = defaults.string(forKey: selected.preferenceKey("baseURL")) ?? selected.defaultBaseURL
        model = defaults.string(forKey: selected.preferenceKey("model")) ?? selected.modelPresets[0]
        thinking = defaults.bool(forKey: selected.preferenceKey("thinking"))
        primary = Language(rawValue: defaults.string(forKey: "primary") ?? "") ?? .chineseSimplified
        secondary = Language(rawValue: defaults.string(forKey: "secondary") ?? "") ?? .english
        translatesPrimary = defaults.bool(forKey: "translatesPrimary")
        trigger = TranslationTrigger(rawValue: defaults.string(forKey: "translationTrigger") ?? "") ?? .automatic
        clipboardFallback = defaults.bool(forKey: "clipboardFallback")
        autoSleepMinutes = defaults.integer(forKey: "autoSleepMinutes")
        petScale = defaults.double(forKey: "petScale").clamped(0.6...1.8)
        visitsSelection = defaults.bool(forKey: "visitsSelection")
        species = Species(rawValue: defaults.string(forKey: "species") ?? "") ?? .cat
        coat = Coat(rawValue: defaults.string(forKey: "coat") ?? "") ?? .orange
        snakeSkin = SnakeSkin(rawValue: defaults.string(forKey: "snakeSkin") ?? "") ?? .mint
        dragonSkin = DragonSkin(rawValue: defaults.string(forKey: "dragonSkin") ?? "") ?? .red
        outfit = OutfitChoice(rawValue: defaults.string(forKey: "outfit") ?? "") ?? .festival
        playsWithCursor = defaults.bool(forKey: "playsWithCursor")
        reactsToTyping = defaults.bool(forKey: "reactsToTyping")
        dancesToMusic = defaults.bool(forKey: "dancesToMusic")
        reactsToBattery = defaults.bool(forKey: "reactsToBattery")
        sitsOnWindows = defaults.bool(forKey: "sitsOnWindows")
        hidesForVideo = defaults.bool(forKey: "hidesForVideo")
        speaksUp = defaults.bool(forKey: "speaksUp")
        greets = defaults.bool(forKey: "greets")
        breakMinutes = defaults.integer(forKey: "breakMinutes")
        remindsOffWork = defaults.bool(forKey: "remindsOffWork")
        offWorkMinute = defaults.integer(forKey: "offWorkMinute").clamped(0...1439)
        remindsBedtime = defaults.bool(forKey: "remindsBedtime")
        bedtimeMinute = defaults.integer(forKey: "bedtimeMinute").clamped(0...1439)
        writesOwnLines = defaults.bool(forKey: "writesOwnLines")
        keepsVocabulary = defaults.bool(forKey: "keepsVocabulary")
        quizzes = defaults.bool(forKey: "quizzes")
        dailySummary = defaults.bool(forKey: "dailySummary")
    }

    var translatorConfig: TranslatorConfig {
        TranslatorConfig(baseURL: baseURL, apiKey: apiKey, model: model, thinking: thinking, service: provider)
    }

    private func loadProvider() {
        loadingProvider = true
        defer { loadingProvider = false }
        let saved = loadKey(provider)
        apiKey = saved.isEmpty ? environment[provider.environmentKey] ?? "" : saved
        baseURL = defaults.string(forKey: provider.preferenceKey("baseURL")) ?? provider.defaultBaseURL
        model = defaults.string(forKey: provider.preferenceKey("model")) ?? provider.modelPresets[0]
        thinking = defaults.bool(forKey: provider.preferenceKey("thinking"))
    }

    var companionPreferences: Companion.Preferences {
        Companion.Preferences(
            greets: greets,
            breakMinutes: breakMinutes,
            offWorkMinute: remindsOffWork ? offWorkMinute : nil,
            bedtimeMinute: remindsBedtime ? bedtimeMinute : nil,
            quizzes: keepsVocabulary && quizzes
        )
    }

    /// The key field updates on every keystroke; the keychain only needs the settled value.
    private func scheduleKeySave() {
        keySave?.cancel()
        keySave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, !Task.isCancelled else { return }
            self.saveKeyNow()
        }
    }

    /// Writes a pending key change immediately, e.g. before quitting.
    func saveKeyNow() {
        guard keySave != nil else { return }
        keySave?.cancel()
        keySave = nil
        storeKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), provider)
    }
}

/// When a selection gets translated.
enum TranslationTrigger: String, CaseIterable, Identifiable, Sendable {
    /// Every selection.
    case automatic
    /// Only a selection made while holding ⌥, or followed by a tap of ⌥ on its own.
    case option

    var id: String { rawValue }

    var name: String {
        switch self {
        case .automatic: "选中就翻译"
        case .option: "按住 ⌥ 选中才翻译"
        }
    }
}
