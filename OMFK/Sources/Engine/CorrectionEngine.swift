import Foundation
import AppKit
import os.log

actor CorrectionEngine {
    private let detector = LanguageDetector()
    private let settings: SettingsManager
    private var history: [CorrectionRecord] = []
    private let logger = Logger.engine
    
    struct CorrectionRecord: Identifiable {
        let id = UUID()
        let original: String
        let corrected: String
        let fromLang: Language
        let toLang: Language
        let timestamp: Date
    }
    
    init(settings: SettingsManager) {
        self.settings = settings
    }
    
    func shouldCorrect(for bundleId: String?) async -> Bool {
        guard await settings.isEnabled else { return false }
        if let id = bundleId, await settings.isExcluded(bundleId: id) {
            return false
        }
        return true
    }
    
    func correctText(_ text: String, expectedLayout: Language?) async -> String? {
        guard !text.isEmpty else { return nil }
        
        logger.info("Correcting text: '\(text, privacy: .public)'")
        
        let detectedLang = await detector.detect(text)
        guard let detected = detectedLang else {
            logger.warning("Failed to detect language for: '\(text, privacy: .public)'")
            return nil
        }
        
        logger.info("Detected language: \(detected.rawValue, privacy: .public)")
        
        // Hybrid algorithm: validate word in detected language
        let isValid = await detector.isValidWord(text, in: detected)
        logger.info("Word '\(text, privacy: .public)' valid in \(detected.rawValue, privacy: .public): \(isValid, privacy: .public)")
        
        if !isValid {
            // Word not found in detected language dictionary, try converting
            let targetLangs: [Language] = detected == .russian ? [.english] :
                                          detected == .hebrew ? [.english] :
                                          [.russian, .hebrew]

            for target in targetLangs {
                if let converted = LayoutMapper.convert(text, from: detected, to: target) {
                    let convertedValid = await detector.isValidWord(converted, in: target)
                    logger.info("Converted '\(text, privacy: .public)' -> '\(converted, privacy: .public)' (\(detected.rawValue, privacy: .public)->\(target.rawValue, privacy: .public)), valid: \(convertedValid, privacy: .public)")
                    if convertedValid {
                        addToHistory(original: text, corrected: converted, from: detected, to: target)
                        // If auto-switch is enabled, switch the actual input source to the target language.
                        if await settings.autoSwitchLayout {
                            await MainActor.run {
                                InputSourceManager.shared.switchTo(language: target)
                            }
                        }
                        return converted
                    }
                }
            }
        }
        
        // Fallback: if expected layout is set and doesn't match detected, correct it
        if let expected = expectedLayout, expected != detected {
            let corrected = LayoutMapper.convert(text, from: detected, to: expected)
            if let result = corrected {
                logger.info("Forced conversion to expected layout: '\(text, privacy: .public)' -> '\(result, privacy: .public)'")
                addToHistory(original: text, corrected: result, from: detected, to: expected)
            }
            return corrected
        }
        
        logger.info("No correction needed for: '\(text, privacy: .public)'")
        return nil
    }
    
    func getHistory() async -> [CorrectionRecord] {
        return history
    }
    
    func clearHistory() async {
        history.removeAll()
    }
    
    func correctLastWord(_ text: String) async -> String? {
        logger.info("Manual correction triggered for: '\(text, privacy: .public)'")
        
        guard !text.isEmpty else { return nil }
        
        let detected = await detector.detect(text)
        guard let from = detected else {
            logger.warning("Cannot detect language for manual correction")
            return nil
        }
        
        // Try all possible conversions
        let targets: [Language] = Language.allCases.filter { $0 != from }
        for target in targets {
            if let converted = LayoutMapper.convert(text, from: from, to: target) {
                logger.info("Manual conversion: '\(text, privacy: .public)' -> '\(converted, privacy: .public)' (\(from.rawValue, privacy: .public)->\(target.rawValue, privacy: .public))")
                addToHistory(original: text, corrected: converted, from: from, to: target)
                return converted
            }
        }
        
        return nil
    }
    
    private func addToHistory(original: String, corrected: String, from: Language, to: Language) {
        let record = CorrectionRecord(
            original: original,
            corrected: corrected,
            fromLang: from,
            toLang: to,
            timestamp: Date()
        )
        history.insert(record, at: 0)
        if history.count > 50 {
            history.removeLast()
        }
    }
}
