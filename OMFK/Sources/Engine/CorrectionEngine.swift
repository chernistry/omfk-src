import Foundation
import AppKit
import os.log

actor CorrectionEngine {
    private let ensemble = LanguageEnsemble()
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
        
        // Use last correction target as context
        var lastLang: Language? = nil
        if let lastRecord = history.first {
            lastLang = lastRecord.toLang
        }
        let context = EnsembleContext(lastLanguage: lastLang)
        
        let decision = await ensemble.classify(text, context: context)
        logger.info("✅ Decision: \(decision.language.rawValue, privacy: .public) (Hypothesis: \(decision.layoutHypothesis.rawValue, privacy: .public), Conf: \(decision.confidence))")
        
        // Check if the decision implies a layout correction
        if decision.layoutHypothesis == .ruFromEnLayout {
            if let corrected = LayoutMapper.convert(text, from: .english, to: .russian) {
                logger.info("✅ VALID CONVERSION FOUND! (Ensemble)")
                return await applyCorrection(original: text, corrected: corrected, from: .english, to: .russian)
            }
        } else if decision.layoutHypothesis == .heFromEnLayout {
            if let corrected = LayoutMapper.convert(text, from: .english, to: .hebrew) {
                logger.info("✅ VALID CONVERSION FOUND! (Ensemble)")
                return await applyCorrection(original: text, corrected: corrected, from: .english, to: .hebrew)
            }
        }
        
        logger.info("ℹ️ No correction needed or found")
        return nil
    }
    
    private func applyCorrection(original: String, corrected: String, from: Language, to: Language) async -> String {
        addToHistory(original: original, corrected: corrected, from: from, to: to)
        
        // If auto-switch is enabled, switch the actual input source to the target language.
        if await settings.autoSwitchLayout {
            logger.info("🔄 Auto-switch enabled - switching input source to \(to.rawValue, privacy: .public)")
            await MainActor.run {
                InputSourceManager.shared.switchTo(language: to)
            }
        }
        return corrected
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
        
        // For manual correction, we try to detect the SOURCE language and flip it.
        // We use ensemble to guess the most likely interpretation, then infer source.
        let decision = await ensemble.classify(text, context: EnsembleContext())
        
        let from: Language
        switch decision.layoutHypothesis {
        case .ru, .enFromRuLayout: from = .russian
        case .en, .ruFromEnLayout, .heFromEnLayout: from = .english
        case .he, .enFromHeLayout: from = .hebrew
        }
        
        logger.info("✅ Inferred source language: \(from.rawValue, privacy: .public)")
        
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
