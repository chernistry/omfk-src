import Foundation
import AppKit

protocol WordValidator {
    /// Returns a normalized confidence in [0, 1] that `text` is a valid word/phrase
    /// in the given language (intended as a short-text signal).
    func confidence(for text: String, language: Language) -> Double
}

struct SystemWordValidator: WordValidator {
    private let spellChecker: NSSpellChecker
    private let languageCodes: [Language: String]

    init(spellChecker: NSSpellChecker = .shared) {
        self.spellChecker = spellChecker
        self.languageCodes = Self.resolveLanguageCodes(available: spellChecker.availableLanguages)
    }

    func confidence(for text: String, language: Language) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.0 }

        // Treat a phrase as "valid" if most words are valid.
        let words = trimmed
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return 0.0 }

        let code = languageCodes[language]
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

    private static func resolveLanguageCodes(available: [String]) -> [Language: String] {
        func pick(_ prefixes: [String]) -> String {
            for prefix in prefixes {
                if let exact = available.first(where: { $0 == prefix }) { return exact }
                if let match = available.first(where: { $0.hasPrefix(prefix) }) { return match }
            }
            return prefixes.first ?? "en"
        }

        return [
            .english: pick(["en_US", "en_GB", "en"]),
            .russian: pick(["ru_RU", "ru"]),
            .hebrew: pick(["he_IL", "he"])
        ]
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

