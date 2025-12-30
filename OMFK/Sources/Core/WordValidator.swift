import Foundation
import AppKit

protocol WordValidator {
    /// Returns a normalized confidence in [0, 1] that `text` is a valid word/phrase
    /// in the given language (intended as a short-text signal).
    func confidence(for text: String, language: Language) -> Double
}

enum BuiltinLexicon {
    private static let config = LanguageDataConfig.shared
    
    static var english: Set<String> { config.lexiconEnglish }
    static var russian: Set<String> { config.lexiconRussian }
    static var hebrew: Set<String> { config.lexiconHebrew }

    static func contains(_ word: String, language: Language) -> Bool {
        config.lexiconContains(word, language: language)
    }
}

struct BuiltinWordValidator: WordValidator {
    func confidence(for text: String, language: Language) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.0 }

        let words = trimmed
            .split(whereSeparator: { !$0.isLetter })
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return 0.0 }
        let hit = words.filter { BuiltinLexicon.contains($0, language: language) }.count
        return Double(hit) / Double(words.count)
    }
}

struct SystemWordValidator: WordValidator {
    private let spellChecker: NSSpellChecker
    private let languageCodes: [Language: String?]

    init(spellChecker: NSSpellChecker = .shared) {
        self.spellChecker = spellChecker
        self.languageCodes = Self.resolveLanguageCodes(available: spellChecker.availableLanguages)
    }

    func confidence(for text: String, language: Language) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.0 }

        guard let code = (languageCodes[language] ?? nil) else { return 0.0 }

        // Treat a phrase as "valid" if most words are valid.
        let words = trimmed
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return 0.0 }

        var valid = 0
        for w in words {
            if isValidWord(w, languageCode: code) { valid += 1 }
        }
        return Double(valid) / Double(words.count)
    }

    private func isValidWord(_ word: String, languageCode: String?) -> Bool {
        // `checkSpelling` returns NSNotFound when there are no misspellings.
        let range = spellChecker.checkSpelling(
            of: word,
            startingAt: 0,
            language: languageCode,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return range.location == NSNotFound
    }

    private static func resolveLanguageCodes(available: [String]) -> [Language: String?] {
        func pick(_ prefixes: [String]) -> String? {
            for prefix in prefixes {
                if let exact = available.first(where: { $0 == prefix }) { return exact }
                if let match = available.first(where: { $0.hasPrefix(prefix) }) { return match }
            }
            return nil
        }

        return [
            .english: pick(["en_US", "en_GB", "en"]),
            .russian: pick(["ru_RU", "ru"]),
            .hebrew: pick(["he_IL", "he"])
        ]
    }
}

/// Uses bundled unigram lists as a deterministic fallback for word validity.
struct BundledWordValidator: WordValidator {
    private let models: [Language: WordFrequencyModel]

    init() {
        var out: [Language: WordFrequencyModel] = [:]
        if let en = try? WordFrequencyModel.loadLanguage("en") { out[.english] = en }
        if let ru = try? WordFrequencyModel.loadLanguage("ru") { out[.russian] = ru }
        if let he = try? WordFrequencyModel.loadLanguage("he") { out[.hebrew] = he }
        self.models = out
    }

    func confidence(for text: String, language: Language) -> Double {
        guard let model = models[language] else { return 0.0 }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.0 }

        let words = trimmed
            .split(whereSeparator: { !$0.isLetter })
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return 0.0 }

        let hit = words.filter { model.contains($0) }.count
        return Double(hit) / Double(words.count)
    }
}

/// Combines system dictionary checks with bundled word lists.
struct HybridWordValidator: WordValidator {
    private let system: SystemWordValidator
    private let bundled: BundledWordValidator
    private let builtin: BuiltinWordValidator
    private let languageData: LanguageDataConfig

    init(
        system: SystemWordValidator = SystemWordValidator(),
        bundled: BundledWordValidator = BundledWordValidator(),
        builtin: BuiltinWordValidator = BuiltinWordValidator(),
        languageData: LanguageDataConfig = .shared
    ) {
        self.system = system
        self.bundled = bundled
        self.builtin = builtin
        self.languageData = languageData
    }

    func confidence(for text: String, language: Language) -> Double {
        let whitelistHit = languageData.isWhitelisted(text, language: language) ? 1.0 : 0.0

        return max(
            system.confidence(for: text, language: language),
            bundled.confidence(for: text, language: language),
            builtin.confidence(for: text, language: language),
            whitelistHit
        )
    }
}

struct MockWordValidator: WordValidator {
    let validWords: [Language: Set<String>]

    func confidence(for text: String, language: Language) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.0 }

        let words = trimmed
            .split(whereSeparator: { !$0.isLetter })
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return 0.0 }
        let dict = validWords[language] ?? []
        let hit = words.filter { dict.contains($0) }.count
        return Double(hit) / Double(words.count)
    }
}
