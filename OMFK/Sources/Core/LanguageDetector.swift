import Foundation
import NaturalLanguage
import AppKit

enum Language: String, CaseIterable {
    case russian = "ru"
    case english = "en"
    case hebrew = "he"
    
    var nlLanguage: NLLanguage {
        switch self {
        case .russian: return .russian
        case .english: return .english
        case .hebrew: return .hebrew
        }
    }
}

actor LanguageDetector {
    private let recognizer = NLLanguageRecognizer()
    private let spellChecker = NSSpellChecker.shared
    
    init() {
        recognizer.languageHints = [
            .russian: 0.33,
            .english: 0.33,
            .hebrew: 0.34
        ]
    }
    
    func detect(_ text: String) async -> Language? {
        guard !text.isEmpty else { return nil }
        
        // Fast path: character set heuristics for short text
        if text.count < 3 {
            return detectByCharacterSet(text)
        }
        
        recognizer.reset()
        recognizer.processString(text)
        
        if let dominant = recognizer.dominantLanguage {
            switch dominant {
            case .russian: return .russian
            case .english: return .english
            case .hebrew: return .hebrew
            default: break
            }
        }
        
        // Fallback to character set
        return detectByCharacterSet(text)
    }
    
    func isValidWord(_ word: String, in language: Language) -> Bool {
        guard !word.isEmpty else { return false }
        spellChecker.setLanguage(language.rawValue)
        let range = spellChecker.checkSpelling(
            of: word,
            startingAt: 0
        )
        return range.location == NSNotFound
    }
    
    private func detectByCharacterSet(_ text: String) -> Language? {
        var ruCount = 0
        var enCount = 0
        var heCount = 0
        
        for char in text.unicodeScalars {
            switch char.value {
            case 0x0410...0x044F: ruCount += 1 // Cyrillic
            case 0x0041...0x005A, 0x0061...0x007A: enCount += 1 // Latin
            case 0x0590...0x05FF: heCount += 1 // Hebrew
            default: break
            }
        }
        
        let max = Swift.max(ruCount, enCount, heCount)
        guard max > 0 else { return nil }
        
        if ruCount == max { return .russian }
        if heCount == max { return .hebrew }
        if enCount == max { return .english }
        return nil
    }
}
