import Foundation
import NaturalLanguage
import AppKit
import os.log

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
    private let logger = Logger.detection
    
    init() {
        recognizer.languageHints = [
            .russian: 0.33,
            .english: 0.33,
            .hebrew: 0.34
        ]
    }
    
    func detect(_ text: String) async -> Language? {
        guard !text.isEmpty else { return nil }
        
        logger.info("🔍 === LANGUAGE DETECTION ===")
        logger.info("Input: '\(text, privacy: .public)' (len=\(text.count))")
        
        // Fast path: character set heuristics for short text
        if text.count < 3 {
            let result = detectByCharacterSet(text)
            logger.info("Short text (<3 chars) - using character set detection: \(result?.rawValue ?? "nil", privacy: .public)")
            return result
        }
        
        recognizer.reset()
        recognizer.processString(text)
        
        if let dominant = recognizer.dominantLanguage {
            logger.info("NLLanguageRecognizer result: \(dominant.rawValue, privacy: .public)")
            switch dominant {
            case .russian:
                logger.info("✅ Detected: Russian")
                return .russian
            case .english:
                logger.info("✅ Detected: English")
                return .english
            case .hebrew:
                logger.info("✅ Detected: Hebrew")
                return .hebrew
            default:
                logger.debug("⚠️ NLLanguageRecognizer returned unsupported language: \(dominant.rawValue, privacy: .public)")
            }
        } else {
            logger.debug("⚠️ NLLanguageRecognizer returned nil")
        }
        
        // Fallback to character set
        let result = detectByCharacterSet(text)
        logger.info("Fallback to character set detection: \(result?.rawValue ?? "nil", privacy: .public)")
        return result
    }
    
    func isValidWord(_ word: String, in language: Language) -> Bool {
        guard !word.isEmpty else { return false }
        
        logger.debug("📖 Spell checking '\(word, privacy: .public)' in \(language.rawValue, privacy: .public)")
        
        spellChecker.setLanguage(language.rawValue)
        let range = spellChecker.checkSpelling(
            of: word,
            startingAt: 0
        )
        let isValid = range.location == NSNotFound
        
        logger.info("📖 Spell check result: '\(word, privacy: .public)' in \(language.rawValue, privacy: .public) = \(isValid ? "VALID" : "INVALID", privacy: .public)")
        
        return isValid
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
        
        logger.debug("Character analysis: RU=\(ruCount), EN=\(enCount), HE=\(heCount)")
        
        let max = Swift.max(ruCount, enCount, heCount)
        guard max > 0 else {
            logger.debug("No recognizable characters found")
            return nil
        }
        
        if ruCount == max {
            logger.debug("Character set detection: Russian (RU=\(ruCount))")
            return .russian
        }
        if heCount == max {
            logger.debug("Character set detection: Hebrew (HE=\(heCount))")
            return .hebrew
        }
        if enCount == max {
            logger.debug("Character set detection: English (EN=\(enCount))")
            return .english
        }
        return nil
    }
}
