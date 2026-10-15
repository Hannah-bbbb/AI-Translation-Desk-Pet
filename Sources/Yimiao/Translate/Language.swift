import Foundation
import NaturalLanguage

enum Language: String, CaseIterable, Identifiable, Sendable {
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case russian = "ru"

    var id: String { rawValue }

    /// Shown in settings and the bubble caption, and how the prompt names the language.
    var name: String {
        switch self {
        case .chineseSimplified: "简体中文"
        case .chineseTraditional: "繁體中文"
        case .english: "English"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        case .russian: "Русский"
        }
    }

    /// Simplified and Traditional count as one language when choosing a direction.
    var family: String { String(rawValue.prefix(2)) }
}

/// Decides which way a piece of text should be translated.
enum LanguageRouter {
    struct Route {
        let target: Language
        /// Where to go if the model finds the text is already in `target`.
        let alternate: Language
        let caption: String
    }

    /// Foreign text goes to the user's own language; text already in it goes to the second
    /// language, or nowhere if that direction is switched off.
    static func route(_ text: String, primary: Language, secondary: Language, translatesPrimary: Bool) -> Route? {
        let source = detect(text)
        if let source, source.family == primary.family {
            guard translatesPrimary, secondary.family != primary.family else { return nil }
            return Route(target: secondary, alternate: primary, caption: "\(source.name) → \(secondary.name)")
        }
        let from = source.map { "\($0.name) " } ?? ""
        return Route(target: primary, alternate: secondary, caption: "\(from)→ \(primary.name)")
    }

    /// Filters out selections that are not prose: numbers, punctuation, links, paths.
    static func isWorthTranslating(_ text: String) -> Bool {
        guard text.unicodeScalars.contains(where: CharacterSet.letters.contains) else { return false }
        if text.count == 1, text.unicodeScalars.allSatisfy(\.isASCII) { return false }
        if !text.contains(where: \.isWhitespace) {
            let isAddress = text.contains("://") || text.hasPrefix("/") || text.hasPrefix("~/")
                || (text.contains("@") && text.contains("."))
            if isAddress { return false }
        }
        return true
    }

    /// The text's language as a two-letter family plus a display name, or nil if unclear.
    static func detect(_ text: String) -> (family: String, name: String)? {
        // CJK is settled by script, which stays reliable even for a single word.
        // Characters are weighed against Latin words, so "这个 API 很慢" still counts as Chinese.
        var han = 0, kana = 0, hangul = 0, words = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            var isLetter = false
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF: han += 1
            case 0x3040...0x30FF: kana += 1
            case 0xAC00...0xD7AF, 0x1100...0x11FF: hangul += 1
            case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x400...0x4FF: isLetter = true
            default: break
            }
            if isLetter, !inWord { words += 1 }
            inWord = isLetter
        }
        if kana > 0, kana + han >= words { return ("ja", "日语") }
        if hangul > 0, hangul >= words { return ("ko", "韩语") }
        if han > 0, han >= words { return ("zh", "中文") }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        // A wrong label in the caption is worse than none, so short guesses need to be confident.
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first, confidence > 0.5 else {
            return nil
        }
        let family = String(language.rawValue.prefix(2))
        let name = Locale(identifier: "zh-Hans").localizedString(forLanguageCode: family) ?? family
        return (family, name)
    }
}
