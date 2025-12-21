import Foundation
import AppKit
import os.log

actor CorrectionEngine {
    private let router: ConfidenceRouter
    private let profile = UserLanguageProfile()
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
        self.router = ConfidenceRouter(settings: settings)
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
        let context = DetectorContext(lastLanguage: lastLang)
        
        let decision = await router.route(token: text, context: context)
        logger.info("✅ Decision: \(decision.language.rawValue, privacy: .public) (Hypothesis: \(decision.layoutHypothesis.rawValue, privacy: .public), Conf: \(decision.confidence))")
        
        // Adjust confidence based on user profile
        let adjustedConfidence = await profile.adjustThreshold(
            for: text,
            lastLanguage: lastLang,
            baseConfidence: decision.confidence
        )
        logger.info("📊 Adjusted confidence: \(decision.confidence) → \(adjustedConfidence)")
        
        // Only apply correction if adjusted confidence is high enough
        let threshold = await settings.standardPathThreshold
        guard adjustedConfidence > threshold else {
            logger.info("⏭️ Skipping correction (confidence too low after adjustment)")
            return nil
        }
        
        // Check if the decision implies a layout correction
        let needsCorrection: Bool
        let sourceLayout: Language
        
        switch decision.layoutHypothesis {
        case .ru, .en, .he:
            // Text is already in correct layout
            needsCorrection = false
            sourceLayout = decision.language
        case .ruFromEnLayout:
            needsCorrection = true
            sourceLayout = .english
        case .heFromEnLayout:
            needsCorrection = true
            sourceLayout = .english
        case .enFromRuLayout:
            needsCorrection = true
            sourceLayout = .russian
        case .enFromHeLayout:
            needsCorrection = true
            sourceLayout = .hebrew
        case .heFromRuLayout:
            needsCorrection = true
            sourceLayout = .russian
        case .ruFromHeLayout:
            needsCorrection = true
            sourceLayout = .hebrew
        }
        
        guard needsCorrection else {
            logger.info("ℹ️ No correction needed - text is in correct layout")
            return nil
        }
        
        // Attempt conversion
        if let corrected = LayoutMapper.shared.convert(text, from: sourceLayout, to: decision.language) {
            logger.info("✅ VALID CONVERSION FOUND! (Ensemble)")
            let result = await applyCorrection(original: text, corrected: corrected, from: sourceLayout, to: decision.language, hypothesis: decision.layoutHypothesis)
            // Record as accepted
            let ctx = ProfileContext(token: text, lastLanguage: lastLang)
            await profile.record(context: ctx, outcome: .accepted, hypothesis: decision.layoutHypothesis)
            return result
        }
        
        logger.info("ℹ️ No correction found")
        return nil
    }
    
    private func applyCorrection(original: String, corrected: String, from: Language, to: Language, hypothesis: LanguageHypothesis) async -> String {
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
        let decision = await router.route(token: text, context: DetectorContext(lastLanguage: nil))
        
        let from: Language
        switch decision.layoutHypothesis {
        case .ru, .enFromRuLayout, .heFromRuLayout: from = .russian
        case .en, .ruFromEnLayout, .heFromEnLayout: from = .english
        case .he, .enFromHeLayout, .ruFromHeLayout: from = .hebrew
        }
        
        logger.info("✅ Inferred source language: \(from.rawValue, privacy: .public)")
        
        // Try all possible conversions
        let targets: [Language] = Language.allCases.filter { $0 != from }
        logger.info("🔄 Trying conversions to: \(targets.map { $0.rawValue }.joined(separator: ", "), privacy: .public)")
        
        for target in targets {
            if let converted = LayoutMapper.shared.convert(text, from: from, to: target) {
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
