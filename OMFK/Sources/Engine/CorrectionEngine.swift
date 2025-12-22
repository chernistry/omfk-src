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
        let timestamp: Date
        let hadTrailingSpace: Bool
        
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
        
        /// Check if cycling state is still valid (60 seconds timeout)
        var isValid: Bool {
            Date().timeIntervalSince(timestamp) < 60.0
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
        logger.info("Input: \(DecisionLogger.tokenSummary(text), privacy: .public)")
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
        let activeLayouts = await settings.activeLayouts
        if let corrected = LayoutMapper.shared.convertBest(text, from: sourceLayout, to: decision.language, activeLayouts: activeLayouts) {
            logger.info("✅ VALID CONVERSION FOUND! (Ensemble)")
            
            // Store cycling state for potential undo
            // Order: [0]=original (undo), [1]=corrected (current), [2+]=other alternatives
            var alternatives: [CyclingState.Alternative] = [
                CyclingState.Alternative(text: text, hypothesis: nil),  // [0] Original (undo target)
                CyclingState.Alternative(text: corrected, hypothesis: decision.layoutHypothesis)  // [1] Corrected
            ]
            
            // Add other possible conversions
            for target in Language.allCases where target != decision.language && target != sourceLayout {
                if let alt = LayoutMapper.shared.convertBest(text, from: sourceLayout, to: target, activeLayouts: activeLayouts), alt != corrected {
                    let hyp = hypothesisFor(source: sourceLayout, target: target)
                    alternatives.append(CyclingState.Alternative(text: alt, hypothesis: hyp))
                }
            }
            
            // currentIndex=1 means we're at corrected; next() will go to 2, then 0 (undo)
            // But we want first hotkey press to UNDO, so we need special handling
            cyclingState = CyclingState(
                originalText: text,
                alternatives: alternatives,
                currentIndex: 1,  // Currently showing corrected
                wasAutomatic: true,
                autoHypothesis: decision.layoutHypothesis,
                timestamp: Date(),
                hadTrailingSpace: true
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
        logger.info("Input: \(DecisionLogger.tokenSummary(text), privacy: .public)")
        
        guard !text.isEmpty else {
            logger.warning("❌ Empty text provided")
            return nil
        }
        
        // Check if we're cycling through alternatives for the same text
        if let state = cyclingState, state.originalText == text || state.alternatives.contains(where: { $0.text == text }) {
            return await cycleCorrection(bundleId: bundleId)
        }
        
        let activeLayouts = await settings.activeLayouts
        
        // Try smart per-segment correction first
        let smartCorrected = await correctPerSegment(text, activeLayouts: activeLayouts)
        
        // Build alternatives with "undo-first" semantics:
        // [0] = original (undo target)
        // [1] = smart correction (per-segment) if different from original
        // [2+] = whole-text conversions
        
        var alternatives: [CyclingState.Alternative] = []
        
        // Detect what the text likely is (for whole-text fallback)
        let decision = await router.route(token: text, context: DetectorContext(lastLanguage: nil), mode: .manual)
        
        // [0] Original text (undo target)
        alternatives.append(CyclingState.Alternative(text: text, hypothesis: nil))
        
        // [1] Smart per-segment correction (if different)
        if let smart = smartCorrected, smart != text {
            alternatives.append(CyclingState.Alternative(text: smart, hypothesis: .ru)) // Best guess
            logger.info("🧠 Smart correction: \(DecisionLogger.tokenSummary(smart), privacy: .public)")
        }
        
        // Generate whole-text conversions as fallback alternatives
        let conversions: [(from: Language, to: Language)] = [
            (.english, .russian),
            (.english, .hebrew),
            (.russian, .english),
            (.russian, .hebrew),
            (.hebrew, .english),
            (.hebrew, .russian),
        ]
        
        var otherAlternatives: [(text: String, hyp: LanguageHypothesis, score: Double)] = []
        
        for (from, to) in conversions {
            if let converted = LayoutMapper.shared.convertBest(text, from: from, to: to, activeLayouts: activeLayouts),
               converted != text,
               !alternatives.contains(where: { $0.text == converted }),
               !otherAlternatives.contains(where: { $0.text == converted }) {
                let hyp = hypothesisFor(source: from, target: to)
                let score = (hyp == decision.layoutHypothesis) ? 1.0 : 0.5
                otherAlternatives.append((text: converted, hyp: hyp, score: score))
            }
        }
        
        otherAlternatives.sort { $0.score > $1.score }
        
        for alt in otherAlternatives {
            alternatives.append(CyclingState.Alternative(text: alt.text, hypothesis: alt.hyp))
        }
        
        guard alternatives.count > 1 else {
            logger.warning("❌ No conversions possible for: \(text)")
            DecisionLogger.shared.log("CORRECTION: No alternatives for '\(text)'")
            return nil
        }
        
        DecisionLogger.shared.log("CORRECTION: Built \(alternatives.count) alternatives for '\(text.prefix(30))...'")
        logger.info("🔄 Built \(alternatives.count) alternatives: original → smart → others")
        
        cyclingState = CyclingState(
            originalText: text,
            alternatives: alternatives,
            currentIndex: 0,
            wasAutomatic: false,
            autoHypothesis: decision.layoutHypothesis,
            timestamp: Date(),
            hadTrailingSpace: false
        )
        
        return await cycleCorrection(bundleId: bundleId)
    }
    
    /// Smart per-segment correction: analyze each word/segment and correct only wrong-layout parts
    private func correctPerSegment(_ text: String, activeLayouts: [String: String]) async -> String? {
        // Split into segments preserving whitespace
        let segments = splitIntoSegments(text)
        guard segments.count > 1 else {
            // Single segment - no benefit from per-segment analysis
            return nil
        }
        
        var result: [String] = []
        var anyChanged = false
        
        for segment in segments {
            // Preserve whitespace as-is
            if segment.allSatisfy({ $0.isWhitespace || $0.isNewline }) {
                result.append(segment)
                continue
            }
            
            // Analyze this segment
            let decision = await router.route(token: segment, context: DetectorContext(lastLanguage: nil), mode: .manual)
            
            // Check if segment needs correction
            let needsCorrection: Bool
            let sourceLayout: Language
            
            switch decision.layoutHypothesis {
            case .ru, .en, .he:
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
            
            if needsCorrection, decision.confidence > 0.4,
               let corrected = LayoutMapper.shared.convertBest(segment, from: sourceLayout, to: decision.language, activeLayouts: activeLayouts) {
                result.append(corrected)
                anyChanged = true
                logger.debug("📝 Segment '\(segment)' → '\(corrected)' (\(decision.layoutHypothesis.rawValue))")
            } else {
                result.append(segment)
            }
        }
        
        return anyChanged ? result.joined() : nil
    }
    
    /// Split text into segments (words + whitespace preserved separately)
    private func splitIntoSegments(_ text: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var inWhitespace = false
        
        for char in text {
            let isWS = char.isWhitespace || char.isNewline
            if isWS != inWhitespace && !current.isEmpty {
                segments.append(current)
                current = ""
            }
            current.append(char)
            inWhitespace = isWS
        }
        if !current.isEmpty {
            segments.append(current)
        }
        return segments
    }
    
    /// Cycle to next alternative on repeated hotkey press
    /// For auto-correction: first press = undo (go to original)
    /// For manual: cycles through alternatives
    func cycleCorrection(bundleId: String? = nil) async -> String? {
        guard var state = cyclingState, state.isValid else {
            logger.warning("❌ No cycling state or expired")
            return nil
        }
        
        // For auto-correction, first hotkey press should UNDO (go to index 0)
        let alt: CyclingState.Alternative
        if state.wasAutomatic && state.currentIndex == 1 {
            // First press after auto-correction: go to original (undo)
            state.currentIndex = 0
            alt = state.alternatives[0]
            logger.info("🔄 UNDO auto-correction → original")
        } else {
            alt = state.next()
        }
        cyclingState = state
        
        logger.info("🔄 Cycling to: \(DecisionLogger.tokenSummary(alt.text), privacy: .public) (index \(state.currentIndex)/\(state.alternatives.count))")
        
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
    
    /// Check if there's an active and valid cycling state
    func hasCyclingState() -> Bool {
        guard let state = cyclingState else { return false }
        return state.isValid
    }
    
    /// Get the length of current cycling text (for replacement)
    func getCurrentCyclingTextLength() -> Int {
        return cyclingState?.current.text.count ?? 0
    }
    
    /// Check if cycling state had trailing space
    func cyclingHadTrailingSpace() -> Bool {
        return cyclingState?.hadTrailingSpace ?? false
    }
    
    /// Get target language from last correction hypothesis
    func getLastCorrectionTargetLanguage() -> Language? {
        guard let hyp = cyclingState?.current.hypothesis else { return nil }
        switch hyp {
        case .ru, .ruFromEnLayout, .ruFromHeLayout: return .russian
        case .en, .enFromRuLayout, .enFromHeLayout: return .english
        case .he, .heFromEnLayout, .heFromRuLayout: return .hebrew
        }
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
        
        // Also update shared HistoryManager for UI
        Task { @MainActor in
            HistoryManager.shared.add(original: original, corrected: corrected, from: from, to: to)
        }
    }
}
