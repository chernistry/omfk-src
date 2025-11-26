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
        let enabled = await settings.isEnabled
        logger.debug("shouldCorrect check: enabled=\(enabled), bundleId=\(bundleId ?? "nil", privacy: .public)")
        
        guard enabled else {
            logger.info("❌ Correction globally disabled")
            return false
        }
        
        if let id = bundleId, await settings.isExcluded(bundleId: id) {
            logger.info("❌ App excluded: \(id, privacy: .public)")
            return false
        }
        
        logger.debug("✅ Correction allowed")
        return true
    }
    
    func correctText(_ text: String, expectedLayout: Language?) async -> String? {
        guard !text.isEmpty else { return nil }
        
        logger.info("🔍 === CORRECTION ATTEMPT ===")
        logger.info("Input: '\(text, privacy: .public)' (len=\(text.count))")
        if let expected = expectedLayout {
            logger.info("Expected layout: \(expected.rawValue, privacy: .public)")
        }
        
        let detectedLang = await detector.detect(text)
        guard let detected = detectedLang else {
            logger.warning("❌ Language detection failed for: '\(text, privacy: .public)'")
            return nil
        }
        
        logger.info("✅ Detected language: \(detected.rawValue, privacy: .public)")
        
        // Hybrid algorithm: always try conversions to find better matches
        // (NSSpellChecker is too liberal for Cyrillic, may accept gibberish)
        let targetLangs: [Language] = detected == .russian ? [.english] :
                                      detected == .hebrew ? [.english] :
                                      [.russian, .hebrew]

        logger.info("Trying conversions to: \(targetLangs.map { $0.rawValue }.joined(separator: ", "), privacy: .public)")

        for target in targetLangs {
            if let converted = LayoutMapper.convert(text, from: detected, to: target) {
                logger.info("🔄 Trying conversion: \(detected.rawValue, privacy: .public) → \(target.rawValue, privacy: .public): '\(text, privacy: .public)' → '\(converted, privacy: .public)'")
                
                let convertedValid = await detector.isValidWord(converted, in: target)
                logger.info("📖 Converted word '\(converted, privacy: .public)' valid in \(target.rawValue, privacy: .public): \(convertedValid ? "YES" : "NO")")
                
                if convertedValid {
                    logger.info("✅ VALID CONVERSION FOUND!")
                    addToHistory(original: text, corrected: converted, from: detected, to: target)
                    
                    // If auto-switch is enabled, switch the actual input source to the target language.
                    if await settings.autoSwitchLayout {
                        logger.info("🔄 Auto-switch enabled - switching input source to \(target.rawValue, privacy: .public)")
                        await MainActor.run {
                            InputSourceManager.shared.switchTo(language: target)
                        }
                    }
                    return converted
                }
            } else {
                logger.debug("⚠️ Conversion failed: \(detected.rawValue, privacy: .public) → \(target.rawValue, privacy: .public)")
            }
        }
        
        logger.info("ℹ️ No valid conversions found")
        return nil
    }
    
    func getHistory() async -> [CorrectionRecord] {
        return history
    }
    
    func clearHistory() async {
        history.removeAll()
    }
    
    func correctLastWord(_ text: String) async -> String? {
        logger.info("🔥 === MANUAL CORRECTION (HOTKEY) ===")
        logger.info("Input: '\(text, privacy: .public)'")
        
        guard !text.isEmpty else {
            logger.warning("❌ Empty text provided")
            return nil
        }
        
        let detected = await detector.detect(text)
        guard let from = detected else {
            logger.warning("❌ Cannot detect language for manual correction")
            return nil
        }
        
        logger.info("✅ Detected language: \(from.rawValue, privacy: .public)")
        
        // Try all possible conversions
        let targets: [Language] = Language.allCases.filter { $0 != from }
        logger.info("🔄 Trying conversions to: \(targets.map { $0.rawValue }.joined(separator: ", "), privacy: .public)")
        
        for target in targets {
            if let converted = LayoutMapper.convert(text, from: from, to: target) {
                logger.info("✅ Manual conversion: '\(text, privacy: .public)' → '\(converted, privacy: .public)' (\(from.rawValue, privacy: .public)→\(target.rawValue, privacy: .public))")
                addToHistory(original: text, corrected: converted, from: from, to: target)
                return converted
            }
        }
        
        logger.warning("❌ No conversions possible")
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
