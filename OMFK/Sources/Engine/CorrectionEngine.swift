import Foundation
import AppKit
import os.log

actor CorrectionEngine {
    private let router: ConfidenceRouter
    private let profile = UserLanguageProfile()
    private let settings: SettingsManager
    private var history: [CorrectionRecord] = []
    private let logger = Logger.engine
    
    // Cycling state for hotkey corrections
    private var cyclingState: CyclingState?
    
    struct CorrectionRecord: Identifiable {
        let id = UUID()
        let original: String
        let corrected: String
        let fromLang: Language
        let toLang: Language
        let timestamp: Date
    }
    
    /// State for cycling through alternatives on repeated hotkey presses
    struct CyclingState {
        let originalText: String
        let alternatives: [Alternative]
        var currentIndex: Int
        let wasAutomatic: Bool
        let autoHypothesis: LanguageHypothesis?
        
        struct Alternative {
            let text: String
            let hypothesis: LanguageHypothesis?
        }
        
        mutating func next() -> Alternative {
            currentIndex = (currentIndex + 1) % alternatives.count
            return alternatives[currentIndex]
        }
        
        var current: Alternative {
            alternatives[currentIndex]
        }
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
            
            // Store cycling state for potential undo
            var alternatives: [CyclingState.Alternative] = [
                CyclingState.Alternative(text: text, hypothesis: nil),  // Original
                CyclingState.Alternative(text: corrected, hypothesis: decision.layoutHypothesis)  // Corrected
            ]
            
            // Add other possible conversions
            for target in Language.allCases where target != decision.language && target != sourceLayout {
                if let alt = LayoutMapper.shared.convert(text, from: sourceLayout, to: target), alt != corrected {
                    let hyp = hypothesisFor(source: sourceLayout, target: target)
                    alternatives.append(CyclingState.Alternative(text: alt, hypothesis: hyp))
                }
            }
            
            cyclingState = CyclingState(
                originalText: text,
                alternatives: alternatives,
                currentIndex: 1,  // Start at corrected version
                wasAutomatic: true,
                autoHypothesis: decision.layoutHypothesis
            )
            
            let result = await applyCorrection(original: text, corrected: corrected, from: sourceLayout, to: decision.language, hypothesis: decision.layoutHypothesis)
            
            // Log for learning
            let bundleId = await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
            CorrectionLogger.shared.log(
                original: text,
                final: corrected,
                autoAttempted: decision.layoutHypothesis,
                userSelected: nil,  // Auto, not user-selected
                app: bundleId
            )
            
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
    
    func correctLastWord(_ text: String, bundleId: String? = nil) async -> String? {
        logger.info("🔥 === MANUAL CORRECTION (HOTKEY) ===")
        logger.info("Input: '\(text, privacy: .public)'")
        
        guard !text.isEmpty else {
            logger.warning("❌ Empty text provided")
            return nil
        }
        
        // Check if we're cycling through alternatives for the same text
        if let state = cyclingState, state.originalText == text || state.alternatives.contains(where: { $0.text == text }) {
            return await cycleCorrection(bundleId: bundleId)
        }
        
        // New text - build alternatives list
        let decision = await router.route(token: text, context: DetectorContext(lastLanguage: nil))
        var alternatives: [CyclingState.Alternative] = []
        
        // First alternative: original text
        alternatives.append(CyclingState.Alternative(text: text, hypothesis: nil))
        
        // Generate all possible conversions
        let sourceLayouts: [Language] = [.english, .russian, .hebrew]
        let targetLanguages: [Language] = [.russian, .english, .hebrew]
        
        for source in sourceLayouts {
            for target in targetLanguages where target != source {
                if let converted = LayoutMapper.shared.convert(text, from: source, to: target), converted != text {
                    let hyp = hypothesisFor(source: source, target: target)
                    if !alternatives.contains(where: { $0.text == converted }) {
                        alternatives.append(CyclingState.Alternative(text: converted, hypothesis: hyp))
                    }
                }
            }
        }
        
        guard alternatives.count > 1 else {
            logger.warning("❌ No conversions possible")
            return nil
        }
        
        // Start cycling from first alternative (which is the conversion, not original)
        cyclingState = CyclingState(
            originalText: text,
            alternatives: alternatives,
            currentIndex: 0,
            wasAutomatic: false,
            autoHypothesis: decision.layoutHypothesis
        )
        
        return await cycleCorrection(bundleId: bundleId)
    }
    
    /// Cycle to next alternative on repeated hotkey press
    func cycleCorrection(bundleId: String? = nil) async -> String? {
        guard var state = cyclingState else {
            logger.warning("❌ No cycling state")
            return nil
        }
        
        let alt = state.next()
        cyclingState = state
        
        logger.info("🔄 Cycling to: '\(alt.text, privacy: .public)' (index \(state.currentIndex)/\(state.alternatives.count))")
        
        // Log the correction for learning
        CorrectionLogger.shared.log(
            original: state.originalText,
            final: alt.text,
            autoAttempted: state.autoHypothesis,
            userSelected: alt.hypothesis,
            app: bundleId
        )
        
        // Record for profile learning
        if let hyp = alt.hypothesis {
            let ctx = ProfileContext(token: state.originalText, lastLanguage: nil)
            await profile.record(context: ctx, outcome: .manual, hypothesis: hyp)
        }
        
        return alt.text
    }
    
    /// Reset cycling state (called when new text is typed)
    func resetCycling() {
        cyclingState = nil
    }
    
    private func hypothesisFor(source: Language, target: Language) -> LanguageHypothesis {
        switch (source, target) {
        case (.english, .russian): return .ruFromEnLayout
        case (.english, .hebrew): return .heFromEnLayout
        case (.russian, .english): return .enFromRuLayout
        case (.russian, .hebrew): return .heFromRuLayout
        case (.hebrew, .english): return .enFromHeLayout
        case (.hebrew, .russian): return .ruFromHeLayout
        default: return .en
        }
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
