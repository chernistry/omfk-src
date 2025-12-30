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
    private var cyclingState: CyclingContext?
    
    // Pending word that was below threshold but might be boosted by context
    private var pendingWord: PendingWord?
    
    // Sentence-level language tracking for context-aware decisions
    private var sentenceDominantLanguage: Language?
    private var sentenceWordCount: Int = 0
    
    /// Word that didn't meet threshold but could be corrected if next word confirms language
    struct PendingWord {
        let text: String
        let decision: LanguageDecision
        let adjustedConfidence: Double
        let timestamp: Date
        let isFirstWord: Bool  // True if this was the first word in sentence
        
        var isValid: Bool { Date().timeIntervalSince(timestamp) < ThresholdsConfig.shared.timing.pendingWordTimeout }
    }
    
    /// Single-letter tokens that map to common Russian prepositions (а в к о у и я)
    private let russianPrepositionMappings: [String: String] = LanguageMappingsConfig.shared.russianPrepositions

    private lazy var unigramModels: [Language: WordFrequencyModel] = {
        var out: [Language: WordFrequencyModel] = [:]
        if let ru = try? WordFrequencyModel.loadLanguage("ru") { out[.russian] = ru }
        if let en = try? WordFrequencyModel.loadLanguage("en") { out[.english] = en }
        if let he = try? WordFrequencyModel.loadLanguage("he") { out[.hebrew] = he }
        return out
    }()
    private let builtinValidator = BuiltinWordValidator()
    private let languageData = LanguageDataConfig.shared
    
    /// Result of correction attempt, may include pending word correction
    struct CorrectionResult {
        let corrected: String?           // Current word correction (nil if no correction)
        let pendingCorrection: String?   // Previous pending word correction (nil if none)
        let pendingOriginal: String?     // Original pending word text (for calculating delete length)
    }
    
    // How much to boost pending word confidence when next word confirms language
    private var contextBoostAmount: Double { ThresholdsConfig.shared.correction.contextBoostAmount }
    
    struct CorrectionRecord: Identifiable {
        let id = UUID()
        let original: String
        let corrected: String
        let fromLang: Language
        let toLang: Language
        let timestamp: Date
    }
    
    /// State for cycling through alternatives on repeated hotkey presses
    struct CyclingContext {
        let originalText: String
        let alternatives: [Alternative]
        var currentIndex: Int
        let wasAutomatic: Bool
        let autoHypothesis: LanguageHypothesis?
        let timestamp: Date
        let hadTrailingSpace: Bool
        
        // Ticket 29: Round-based cycling
        var roundNumber: Int = 1
        var visibleAlternativesCount: Int
        var cycleCount: Int = 0 // Tracks how many times we wrapped 0->1->0
        var hasReturnedToOriginal: Bool = false // Track if user returned to index 0 after auto-correction
        
        struct Alternative {
            let text: String
            let hypothesis: LanguageHypothesis?
        }
        
        mutating func next() -> Alternative {
            let limit = visibleAlternativesCount
            let nextIndex = (currentIndex + 1)
            
            if nextIndex >= limit {
                currentIndex = 0
            } else {
                currentIndex = nextIndex
            }
            
            // Track first return to original after auto-correction
            if wasAutomatic && currentIndex == 0 && !hasReturnedToOriginal {
                hasReturnedToOriginal = true
            }
            
            return alternatives[currentIndex]
        }
        
        var current: Alternative {
            alternatives[currentIndex]
        }
        
        /// Check if cycling state is still valid (configurable timeout)
        var isValid: Bool {
            Date().timeIntervalSince(timestamp) < ThresholdsConfig.shared.timing.cyclingStateTimeout
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
    
    func correctText(_ text: String, expectedLayout: Language?) async -> CorrectionResult {
        guard !text.isEmpty else { return CorrectionResult(corrected: nil, pendingCorrection: nil, pendingOriginal: nil) }
        
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
        var adjustedConfidence = await profile.adjustThreshold(
            for: text,
            lastLanguage: lastLang,
            baseConfidence: decision.confidence
        )
        logger.info("📊 Adjusted confidence: \(decision.confidence) → \(adjustedConfidence)")
        
        // Check if we should boost and correct a pending word based on this word's language
        var pendingCorrectionResult: String? = nil
        var pendingOriginalText: String? = nil
        let threshold = await settings.standardPathThreshold
        
        // Determine the target language of current word (what it should become after correction)
        let currentTargetLang = decision.layoutHypothesis.targetLanguage
        
        print("🔍 DEBUG: text='\(text)' pending=\(pendingWord?.text ?? "nil") currentTargetLang=\(currentTargetLang.rawValue)")
        fflush(stdout)
        
        if let pending = pendingWord, pending.isValid {
            print("📌 DEBUG: Checking pending word: '\(pending.text)' isFirst=\(pending.isFirstWord) conf=\(pending.adjustedConfidence)")
            print("📌 DEBUG: Current word decision: lang=\(decision.language.rawValue) hyp=\(decision.layoutHypothesis.rawValue) conf=\(adjustedConfidence) targetLang=\(currentTargetLang.rawValue)")
            
            // Special handling for first-word Russian prepositions - check this FIRST
            if pending.isFirstWord,
               pending.text.count == 1,
               let expectedRu = russianPrepositionMappings[pending.text.lowercased()],
               (currentTargetLang == .russian || adjustedConfidence > threshold && decision.layoutHypothesis.rawValue.contains("ru")) {
                // First word is single letter that maps to Russian preposition, and current word is Russian
                // Use our direct mapping instead of LayoutMapper (more reliable for single chars)
                let corrected = pending.text.first?.isUppercase == true ? expectedRu.uppercased() : expectedRu
                _ = await applyCorrection(original: pending.text, corrected: corrected, from: .english, to: .russian, hypothesis: .ruFromEnLayout)
                pendingCorrectionResult = corrected
                pendingOriginalText = pending.text
                print("✅ DEBUG: First-word preposition corrected: '\(pending.text)' → '\(corrected)'")
            }
            // Standard context boost: if current word is high confidence and same language as pending word's decision
            else if adjustedConfidence > threshold && currentTargetLang == pending.decision.layoutHypothesis.targetLanguage {
                let boostedConfidence = pending.adjustedConfidence + contextBoostAmount
                logger.info("🔗 Context boost: pending '\(pending.text)' \(pending.adjustedConfidence) → \(boostedConfidence)")
                
                if boostedConfidence > threshold {
                    // Now the pending word passes threshold - correct it too
                    if let corrected = await applyCorrection(pending.text, decision: pending.decision) {
                        pendingCorrectionResult = corrected
                        pendingOriginalText = pending.text
                        logger.info("✅ Pending word corrected via context boost: '\(pending.text)' → '\(corrected)'")
                    }
                }
            }
            pendingWord = nil  // Clear pending regardless
        }

        // Smart handling for tokens with internal punctuation/symbols:
        // - If punctuation is actually a mapped RU/HE letter (e.g. "k.,k.", "cj;fktyb."), whole-token conversion should win.
        // - If punctuation is a separator between multiple words (e.g. "ghbdtn.rfr"), split + per-word conversion should win.
        if text.contains(where: { !$0.isLetter && !$0.isNumber }) {
            let activeLayouts = await settings.activeLayouts
            if let smart = await bestSmartCorrection(
                for: text,
                wholeDecision: decision,
                wholeConfidence: adjustedConfidence,
                context: context,
                activeLayouts: activeLayouts,
                mode: .automatic,
                minConfidence: threshold
            ) {
                if let hyp = smart.hypothesis, let from = smart.from, let to = smart.to {
                    let applied = await applyCorrection(original: text, corrected: smart.text, from: from, to: to, hypothesis: hyp)
                    if sentenceDominantLanguage == nil {
                        sentenceDominantLanguage = to
                        sentenceWordCount = 1
                    } else if sentenceDominantLanguage == to {
                        sentenceWordCount += 1
                    }
                    return CorrectionResult(corrected: applied, pendingCorrection: pendingCorrectionResult, pendingOriginal: pendingOriginalText)
                }
                return CorrectionResult(corrected: smart.text, pendingCorrection: pendingCorrectionResult, pendingOriginal: pendingOriginalText)
            }
        }
        
        // Update sentence dominant language when we have high confidence
        if adjustedConfidence > threshold {
            let targetLang = decision.layoutHypothesis.targetLanguage
            if sentenceDominantLanguage == nil {
                sentenceDominantLanguage = targetLang
                sentenceWordCount = 1
            } else if targetLang == sentenceDominantLanguage {
                sentenceWordCount += 1
            }
        }
        
        // Only apply correction if adjusted confidence is high enough
        guard adjustedConfidence > threshold else {
            logger.info("⏭️ Skipping correction (confidence too low after adjustment)")
            
            // Store as pending if confidence is in "uncertain" range (e.g., 0.4-0.7)
            let minPendingConfidence = ThresholdsConfig.shared.timing.pendingWordMinConfidence
            // For single-letter tokens that could be Russian prepositions, lower the threshold
            let isPrepositionCandidate = text.count == 1 && russianPrepositionMappings[text.lowercased()] != nil
            let effectiveMinConfidence = isPrepositionCandidate ? ThresholdsConfig.shared.timing.prepositionMinConfidence : minPendingConfidence
            
            if adjustedConfidence >= effectiveMinConfidence || isPrepositionCandidate {
                let isFirst = sentenceWordCount == 0 && pendingWord == nil
                pendingWord = PendingWord(
                    text: text,
                    decision: decision,
                    adjustedConfidence: adjustedConfidence,
                    timestamp: Date(),
                    isFirstWord: isFirst
                )
                print("📌 DEBUG: Stored as pending word: '\(text)' conf=\(adjustedConfidence) isFirst=\(isFirst) prepositionCandidate=\(isPrepositionCandidate)")
            }
            
            return CorrectionResult(corrected: nil, pendingCorrection: pendingCorrectionResult, pendingOriginal: pendingOriginalText)
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
	            // Context override for short ambiguous tokens inside a strong sentence.
	            // Example: "vs" should become "мы" inside a Russian sentence.
	            if let dominant = sentenceDominantLanguage,
	               dominant != decision.language,
	               sentenceWordCount >= 2,
	               text.count <= 2,
	               text.allSatisfy({ $0.isLetter }) {
	                let activeLayouts = await settings.activeLayouts
	                if let override = shortTokenDominantOverride(token: text, from: decision.language, to: dominant, activeLayouts: activeLayouts) {
	                    let applied = await applyCorrection(
	                        original: text,
	                        corrected: override.corrected,
	                        from: override.from,
	                        to: override.to,
	                        hypothesis: override.hypothesis
	                    )
	                    return CorrectionResult(corrected: applied, pendingCorrection: pendingCorrectionResult, pendingOriginal: pendingOriginalText)
	                }
	            }

            logger.info("ℹ️ No correction needed - text is in correct layout, but creating cycling state for manual override")
            
            // Even if no correction needed, create cycling state so user can force-convert
            let activeLayouts = await settings.activeLayouts
            var alternatives: [CyclingContext.Alternative] = [
                CyclingContext.Alternative(text: text, hypothesis: decision.layoutHypothesis)  // [0] Original (current)
            ]
            
            // Add conversions to other languages
            for target in Language.allCases where target != decision.language {
                if let alt = LayoutMapper.shared.convertBest(text, from: decision.language, to: target, activeLayouts: activeLayouts), alt != text {
                    let hyp = hypothesisFor(source: decision.language, target: target)
                    alternatives.append(CyclingContext.Alternative(text: alt, hypothesis: hyp))
                }
            }
            
            if alternatives.count > 1 {
                cyclingState = CyclingContext(
                    originalText: text,
                    alternatives: alternatives,
                    currentIndex: 0,  // Currently showing original
                    wasAutomatic: false,  // No auto-correction happened
                    autoHypothesis: decision.layoutHypothesis,
                    timestamp: Date(),
                    hadTrailingSpace: true,
                    visibleAlternativesCount: min(alternatives.count, ThresholdsConfig.shared.correction.visibleAlternativesRound1),
                    cycleCount: 0
                )
            }
            
            return CorrectionResult(corrected: nil, pendingCorrection: pendingCorrectionResult, pendingOriginal: pendingOriginalText)
        }
        
        // Attempt conversion - try ALL target layout variants
        let activeLayouts = await settings.activeLayouts
        let variants = LayoutMapper.shared.convertAllVariants(text, from: sourceLayout, to: decision.language, activeLayouts: activeLayouts)
        
        // Pick the variant that's in the builtin lexicon, or first one if none match
        var corrected: String? = nil
        for (_, converted) in variants {
            if BuiltinLexicon.contains(converted, language: decision.language) {
                corrected = converted
                break
            }
            if corrected == nil {
                corrected = converted
            }
        }
        
        if let corrected = corrected {
            logger.info("✅ VALID CONVERSION FOUND! (Ensemble)")
            
            // Store cycling state for potential undo
            // Order: [0]=original (undo), [1]=corrected (current), [2+]=other alternatives
            var alternatives: [CyclingContext.Alternative] = [
                CyclingContext.Alternative(text: text, hypothesis: nil),  // [0] Original (undo target)
                CyclingContext.Alternative(text: corrected, hypothesis: decision.layoutHypothesis)  // [1] Corrected
            ]
            
            // Add other possible conversions
            for target in Language.allCases where target != decision.language && target != sourceLayout {
                if let alt = LayoutMapper.shared.convertBest(text, from: sourceLayout, to: target, activeLayouts: activeLayouts), alt != corrected {
                    let hyp = hypothesisFor(source: sourceLayout, target: target)
                    alternatives.append(CyclingContext.Alternative(text: alt, hypothesis: hyp))
                }
            }
            
            // currentIndex=1 means we're at corrected; next() will go to 2, then 0 (undo)
            // But we want first hotkey press to UNDO, so we need special handling
            cyclingState = CyclingContext(
                originalText: text,
                alternatives: alternatives,
                currentIndex: 1,  // Currently showing corrected
                wasAutomatic: true,
                autoHypothesis: decision.layoutHypothesis,
                timestamp: Date(),
                hadTrailingSpace: true,
                visibleAlternativesCount: min(alternatives.count, ThresholdsConfig.shared.correction.visibleAlternativesRound1),
                cycleCount: 0
            )
            
            let correctedText = await applyCorrection(original: text, corrected: corrected, from: sourceLayout, to: decision.language, hypothesis: decision.layoutHypothesis)
            
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
            return CorrectionResult(corrected: correctedText, pendingCorrection: pendingCorrectionResult, pendingOriginal: pendingOriginalText)
        }
        
        logger.info("ℹ️ No correction found")
        return CorrectionResult(corrected: nil, pendingCorrection: pendingCorrectionResult, pendingOriginal: pendingOriginalText)
    }
    
    private func applyCorrection(original: String, corrected: String, from: Language, to: Language, hypothesis: LanguageHypothesis) async -> String {
        addToHistory(original: original, corrected: corrected, from: from, to: to)
        
        // If auto-switch is enabled, switch the actual input source to the target language.
        if await settings.autoSwitchLayout {
            logger.info("🔄 Auto-switch enabled - switching input source to \(to.rawValue, privacy: .public)")
            let activeLayouts = await settings.activeLayouts
            await MainActor.run {
                if let preferredLayout = activeLayouts[to.rawValue],
                   InputSourceManager.shared.switchToLayoutVariant(preferredLayout) {
                    // Switched to the user's configured variant.
                } else {
                    InputSourceManager.shared.switchTo(language: to)
                }
            }
        }
        return corrected
    }
    
    /// Apply correction based on a decision (for pending word boost)
    private func applyCorrection(_ text: String, decision: LanguageDecision) async -> String? {
        let sourceLayout: Language
        switch decision.layoutHypothesis {
        case .ru, .en, .he: return nil  // No correction needed
        case .ruFromEnLayout, .heFromEnLayout: sourceLayout = .english
        case .enFromRuLayout, .heFromRuLayout: sourceLayout = .russian
        case .enFromHeLayout, .ruFromHeLayout: sourceLayout = .hebrew
        }
        
        let activeLayouts = await settings.activeLayouts
        let variants = LayoutMapper.shared.convertAllVariants(text, from: sourceLayout, to: decision.language, activeLayouts: activeLayouts)

        var corrected: String? = nil
        for (_, converted) in variants {
            if BuiltinLexicon.contains(converted, language: decision.language) {
                corrected = converted
                break
            }
            if corrected == nil {
                corrected = converted
            }
        }

        guard let corrected else { return nil }
        
        return await applyCorrection(original: text, corrected: corrected, from: sourceLayout, to: decision.language, hypothesis: decision.layoutHypothesis)
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
        
        // Note: cycling is now managed by EventMonitor, not here
        // This function always creates fresh alternatives
        
        let activeLayouts = await settings.activeLayouts
        
        // Try smart per-segment correction first
        let smartCorrected = await correctPerSegment(text, activeLayouts: activeLayouts)
        
        // Build alternatives with "undo-first" semantics:
        // [0] = original (undo target)
        // [1] = primary whole-text correction for dominant hypothesis (if available)
        // [2] = smart per-segment correction (if available)
        // [3+] = other whole-text conversions
        
        var alternatives: [CyclingContext.Alternative] = []
        
        // Detect what the text likely is (for whole-text fallback)
        let decision = await router.route(token: text, context: DetectorContext(lastLanguage: nil), mode: .manual)
        
        // [0] Original text (undo target)
        alternatives.append(CyclingContext.Alternative(text: text, hypothesis: nil))

        // Generate whole-text conversions. We'll pick the most plausible one as the primary correction
        // for the first hotkey press (round 1), then keep the rest for cycling.
        let conversions = LanguageMappingsConfig.shared.languageConversions

        var candidates: [(text: String, hyp: LanguageHypothesis, quality: Double, bonus: Double)] = []
        candidates.reserveCapacity(conversions.count)

        var seen = Set<String>()
        seen.insert(text)

        for (from, to) in conversions {
            let hyp = hypothesisFor(source: from, target: to)
            let variants = LayoutMapper.shared.convertAllVariants(text, from: from, to: to, activeLayouts: activeLayouts)

            guard let converted = variants.lazy.map(\.result).first(where: { candidate in
                candidate != text && seen.insert(candidate).inserted
            }) else {
                continue
            }

            // Pick best-looking output by lightweight scoring. This strongly prefers real words
            // like "привет" over script-consistent but meaningless strings like "עינגאמ".
            let quality = fastTextScore(converted)
            let bonus = (hyp == decision.layoutHypothesis) ? 0.20 : 0.0
            candidates.append((text: converted, hyp: hyp, quality: quality, bonus: bonus))
        }

        let primaryWhole = candidates.max(by: { ($0.quality + $0.bonus) < ($1.quality + $1.bonus) })

        // Prefer smart-per-segment correction when it clearly looks better (especially for punctuation separators),
        // otherwise keep the best whole-text conversion as primary.
        let smartCandidate: (text: String, score: Double)? = {
            guard let smart = smartCorrected, smart != text else { return nil }
            return (text: smart, score: fastTextScore(smart))
        }()

        enum PrimaryKind { case smart, whole }
        let primaryKind: PrimaryKind
        if let smartCandidate {
            if let primaryWhole {
                let wholeScore = primaryWhole.quality + primaryWhole.bonus
                // Small bias towards the smart candidate because it tends to preserve punctuation semantics.
                primaryKind = (smartCandidate.score + 0.05 >= wholeScore) ? .smart : .whole
            } else {
                primaryKind = .smart
            }
        } else {
            primaryKind = .whole
        }

        // [1] Primary correction: smart or whole-text depending on quality.
        switch primaryKind {
        case .smart:
            if let smartCandidate {
                alternatives.append(CyclingContext.Alternative(text: smartCandidate.text, hypothesis: nil))
                logger.info("🧠 Smart correction (primary): \(DecisionLogger.tokenSummary(smartCandidate.text), privacy: .public)")
                seen.insert(smartCandidate.text)
            }
        case .whole:
            if let primaryWhole {
                alternatives.append(CyclingContext.Alternative(text: primaryWhole.text, hypothesis: primaryWhole.hyp))
            }
        }

        // [2] Secondary: include the other candidate (if it exists and is different).
        if primaryKind == .smart, let primaryWhole, seen.insert(primaryWhole.text).inserted {
            alternatives.append(CyclingContext.Alternative(text: primaryWhole.text, hypothesis: primaryWhole.hyp))
        } else if primaryKind == .whole, let smartCandidate, seen.insert(smartCandidate.text).inserted {
            alternatives.append(CyclingContext.Alternative(text: smartCandidate.text, hypothesis: nil))
            logger.info("🧠 Smart correction: \(DecisionLogger.tokenSummary(smartCandidate.text), privacy: .public)")
        }

        // [3+] Remaining whole-text conversions (stable order: best first)
        candidates
            .sorted(by: { ($0.quality + $0.bonus) > ($1.quality + $1.bonus) })
            .forEach { cand in
                guard cand.text != primaryWhole?.text else { return }
                alternatives.append(CyclingContext.Alternative(text: cand.text, hypothesis: cand.hyp))
            }
        
        guard alternatives.count > 1 else {
            logger.warning("❌ No conversions possible for: \(text)")
            DecisionLogger.shared.log("CORRECTION: No alternatives for '\(text)'")
            return nil
        }
        
        DecisionLogger.shared.log("CORRECTION: Built \(alternatives.count) alternatives for '\(text.prefix(30))...'")
        logger.info("🔄 Built \(alternatives.count) alternatives: original → smart → others")
        
        cyclingState = CyclingContext(
            originalText: text,
            alternatives: alternatives,
            currentIndex: 0,
            wasAutomatic: false,
            autoHypothesis: decision.layoutHypothesis,
            timestamp: Date(),
            hadTrailingSpace: false,
            visibleAlternativesCount: min(alternatives.count, ThresholdsConfig.shared.correction.visibleAlternativesRound1),
            cycleCount: 0
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

        var out = ""
        out.reserveCapacity(text.count)
        var anyChanged = false

        let context = DetectorContext(lastLanguage: nil)

        for segment in segments {
            // Preserve whitespace as-is
            if segment.allSatisfy({ $0.isWhitespace || $0.isNewline }) {
                out.append(segment)
                continue
            }

            if let smart = await bestSmartCorrection(
                for: segment,
                wholeDecision: nil,
                wholeConfidence: nil,
                context: context,
                activeLayouts: activeLayouts,
                mode: .manual,
                minConfidence: 0.25
            ) {
                out.append(smart.text)
                anyChanged = true
            } else {
                out.append(segment)
            }
        }

        return anyChanged ? out : nil
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

    private struct SmartCorrection: Sendable {
        let text: String
        let hypothesis: LanguageHypothesis?
        let from: Language?
        let to: Language?
        let score: Double
    }

    private struct CompoundPart: Sendable {
        let isWord: Bool
        let text: String
    }

    private func languages(for hypothesis: LanguageHypothesis) -> (source: Language, target: Language)? {
        switch hypothesis {
        case .ruFromEnLayout: return (.english, .russian)
        case .heFromEnLayout: return (.english, .hebrew)
        case .enFromRuLayout: return (.russian, .english)
        case .heFromRuLayout: return (.russian, .hebrew)
        case .enFromHeLayout: return (.hebrew, .english)
        case .ruFromHeLayout: return (.hebrew, .russian)
        case .ru, .en, .he: return nil
        }
    }

    private func fastWordScore(_ word: String, language: Language) -> Double {
        let trimmed = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.0 }
        let unigramRaw = unigramModels[language]?.score(trimmed) ?? 0.0
        // Ignore ultra-rare unigram hits for English (they often include gibberish-like tokens).
        let unigram: Double
        switch language {
        case .english:
            unigram = unigramRaw >= 0.20 ? unigramRaw : 0.0
        case .russian, .hebrew:
            unigram = unigramRaw
        }
        let builtin = builtinValidator.confidence(for: trimmed, language: language)
        return max(unigram, builtin)
    }

    private func bestWordScore(_ word: String) -> Double {
        max(
            fastWordScore(word, language: .english),
            fastWordScore(word, language: .russian),
            fastWordScore(word, language: .hebrew)
        )
    }

    private func fastTextScore(_ text: String) -> Double {
        let words = text
            .split(whereSeparator: { !$0.isLetter })
            .map { String($0) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return 0.0 }
        return words.reduce(0.0) { $0 + bestWordScore($1) }
    }

    private func splitWordRunsAndDelimiters(_ text: String) -> [CompoundPart] {
        guard !text.isEmpty else { return [] }

        var parts: [CompoundPart] = []
        parts.reserveCapacity(min(16, text.count))

        var current = ""
        current.reserveCapacity(min(16, text.count))
        var inWord: Bool? = nil

        func flush() {
            guard !current.isEmpty, let inWord else { return }
            parts.append(CompoundPart(isWord: inWord, text: current))
            current.removeAll(keepingCapacity: true)
        }

        for ch in text {
            let isWordChar = ch.isLetter || ch.isNumber
            if let inWord, inWord != isWordChar {
                flush()
            }
            inWord = isWordChar
            current.append(ch)
        }
        flush()
        return parts
    }

    private func buildWholeCandidate(
        token: String,
        decision: LanguageDecision,
        confidence: Double,
        activeLayouts: [String: String],
        minConfidence: Double
    ) -> SmartCorrection {
        if decision.layoutHypothesis.rawValue.contains("_from_"),
           confidence >= minConfidence,
           let (source, target) = languages(for: decision.layoutHypothesis),
           let converted = LayoutMapper.shared.convertBest(token, from: source, to: target, activeLayouts: activeLayouts),
           converted != token {
            return SmartCorrection(
                text: converted,
                hypothesis: decision.layoutHypothesis,
                from: source,
                to: target,
                score: fastTextScore(converted)
            )
        }
        return SmartCorrection(text: token, hypothesis: nil, from: nil, to: nil, score: fastTextScore(token))
    }

    private func buildSplitCandidate(
        token: String,
        context: DetectorContext,
        activeLayouts: [String: String],
        mode: DetectionMode,
        minConfidence: Double
    ) async -> SmartCorrection {
        let parts = splitWordRunsAndDelimiters(token)
        guard !parts.isEmpty else {
            return SmartCorrection(text: token, hypothesis: nil, from: nil, to: nil, score: 0.0)
        }

        var result = ""
        result.reserveCapacity(token.count)

        var hypCounts: [LanguageHypothesis: Int] = [:]

        for part in parts {
            guard part.isWord else {
                result.append(part.text)
                continue
            }

            let decision = await router.route(token: part.text, context: context, mode: mode)
            if decision.layoutHypothesis.rawValue.contains("_from_"),
               decision.confidence >= minConfidence,
               let (source, target) = languages(for: decision.layoutHypothesis),
               let corrected = LayoutMapper.shared.convertBest(part.text, from: source, to: target, activeLayouts: activeLayouts),
               corrected != part.text {
                result.append(corrected)
                hypCounts[decision.layoutHypothesis, default: 0] += 1
            } else {
                result.append(part.text)
            }
        }

        let dominantHypothesis = hypCounts.max(by: { $0.value < $1.value })?.key
        let langPair = dominantHypothesis.flatMap(languages(for:))

        return SmartCorrection(
            text: result,
            hypothesis: dominantHypothesis,
            from: langPair?.source,
            to: langPair?.target,
            score: fastTextScore(result)
        )
    }

    private func shouldPreferSplitOverWholeForDotCommaSeparator(
        original: String,
        split: SmartCorrection,
        whole: SmartCorrection
    ) -> Bool {
        // If the original contains "." or "," between two reasonably long word runs, treat it as a separator,
        // and prefer the split candidate when whole-token conversion "swallows" the punctuation by mapping it to a letter.
        // Example: "ghbdtn.rfr" should become "привет.как", not "приветюкак".
        let parts = splitWordRunsAndDelimiters(original)
        guard parts.count >= 3 else { return false }

        for i in 1..<(parts.count - 1) {
            guard !parts[i].isWord else { continue }
            let delim = parts[i].text
            guard delim == "." || delim == "," else { continue }
            guard parts[i - 1].isWord, parts[i + 1].isWord else { continue }

            let leftLetters = parts[i - 1].text.filter { $0.isLetter }.count
            let rightLetters = parts[i + 1].text.filter { $0.isLetter }.count
            guard leftLetters >= 2, rightLetters >= 2 else { continue }

            if split.text.contains(delim), !whole.text.contains(delim) {
                return true
            }
        }

        return false
    }

    private func bestSmartCorrection(
        for token: String,
        wholeDecision: LanguageDecision?,
        wholeConfidence: Double?,
        context: DetectorContext,
        activeLayouts: [String: String],
        mode: DetectionMode,
        minConfidence: Double
    ) async -> SmartCorrection? {
        let originalScore = fastTextScore(token)

        let decision: LanguageDecision
        if let wholeDecision {
            decision = wholeDecision
        } else {
            decision = await router.route(token: token, context: context, mode: mode)
        }

        let confidence = wholeConfidence ?? decision.confidence

        let whole = buildWholeCandidate(
            token: token,
            decision: decision,
            confidence: confidence,
            activeLayouts: activeLayouts,
            minConfidence: minConfidence
        )
        let split = await buildSplitCandidate(
            token: token,
            context: context,
            activeLayouts: activeLayouts,
            mode: mode,
            minConfidence: minConfidence
        )

        let best: SmartCorrection
        if whole.hypothesis != nil {
            if shouldPreferSplitOverWholeForDotCommaSeparator(original: token, split: split, whole: whole) {
                best = split
            } else {
            // When the router thinks whole-token correction is valid, only switch to split-mode
            // if it's meaningfully better. This avoids flipping to a different language just
            // because a short split-part looks "valid" by score.
                best = (split.score > whole.score + 0.25) ? split : whole
            }
        } else {
            // No strong whole-token correction → prefer split on ties.
            best = (split.score >= whole.score) ? split : whole
        }
        guard best.text != token else { return nil }
        // If our fast scoring can't distinguish (e.g. missing lexicon form),
        // still allow correction when the original scored as pure "unknown".
        if best.score > originalScore || (best.hypothesis != nil && originalScore == 0.0) {
            return best
        }
        return nil
    }

    private struct ShortTokenOverride: Sendable {
        let corrected: String
        let hypothesis: LanguageHypothesis
        let from: Language
        let to: Language
    }

    private func shortTokenDominantOverride(
        token: String,
        from: Language,
        to: Language,
        activeLayouts: [String: String]
    ) -> ShortTokenOverride? {
        guard from != to else { return nil }
        guard token.count <= 2 else { return nil }
        guard token.allSatisfy({ $0.isLetter }) else { return nil }

        let hyp = hypothesisFor(source: from, target: to)
        guard hyp.rawValue.contains("_from_") else { return nil }

        guard let converted = LayoutMapper.shared.convertBest(token, from: from, to: to, activeLayouts: activeLayouts),
              converted != token else { return nil }

        let sourceScore = fastWordScore(token, language: from)
        let targetScore = fastWordScore(converted, language: to)

        // Only override when the target is a clearly better/common word in the dominant language.
        guard targetScore >= 0.70, targetScore >= sourceScore + 0.25 else { return nil }

        return ShortTokenOverride(corrected: converted, hypothesis: hyp, from: from, to: to)
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
        let alt: CyclingContext.Alternative
        
        if state.wasAutomatic && state.currentIndex == 1 {
            // First press after auto-correction: go to original (undo)
            state.currentIndex = 0
            alt = state.alternatives[0]
            logger.info("🔄 UNDO auto-correction → original")
        } else {
            // Check if we need to expand rounds
            let nextIndex = state.currentIndex + 1
            
            if nextIndex >= state.visibleAlternativesCount {
                // We are about to wrap.
                if state.roundNumber == 1 {
                    if state.cycleCount >= 1 {
                        // We have already wrapped at least once (0 -> 1 -> 0 -> 1 -> [here])
                        // Time to expand to Round 2
                        if state.alternatives.count > state.visibleAlternativesCount {
                            state.roundNumber = 2
                            state.visibleAlternativesCount = min(state.alternatives.count, ThresholdsConfig.shared.correction.visibleAlternativesRound2)
                            logger.info("🔄 Entering Round 2: Visible alternatives increased to \(state.visibleAlternativesCount)")
                        }
                    }
                    
                    // Increment cycle count on wrap (or failed expansion)
                    // Note: If we expanded, nextIndex (2) is < 3, so we might NOT wrap in next().
                    // But if we expanded, we don't increment cycleCount?
                    // Let's increment cycleCount only when we actually WRAP (go to 0).
                    
                    if nextIndex >= state.visibleAlternativesCount {
                        state.cycleCount += 1
                    }
                }
            }
            
            alt = state.next()
        }
        cyclingState = state
        
        logger.info("🔄 Cycling to: \(DecisionLogger.tokenSummary(alt.text), privacy: .public) (index \(state.currentIndex)/\(state.alternatives.count), round \(state.roundNumber))")
        
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
        // Commit learning before clearing state
        if let state = cyclingState, state.isValid {
             Task {
                 let finalIndex = state.currentIndex
                 let finalAlt = state.alternatives[finalIndex]
                 let token = state.originalText
                 let bundleId = await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
                 
                 DecisionLogger.shared.log("LEARNING: token='\(token)' finalIndex=\(finalIndex) wasAutomatic=\(state.wasAutomatic) hypothesis=\(finalAlt.hypothesis?.rawValue ?? "nil")")
                 
                 if state.wasAutomatic {
                     if finalIndex == 0 && state.hasReturnedToOriginal {
                         // 1. Learn from Undo (AutoReject) - only if user actually returned to original
                         DecisionLogger.shared.log("LEARNING: recordAutoReject for '\(token)'")
                         await UserDictionary.shared.recordAutoReject(token: token, bundleId: bundleId)
                     } else if finalIndex != 1 {
                         // 2. User changed auto-correction to different hypothesis (ManualApply)
                         if let hyp = finalAlt.hypothesis {
                             DecisionLogger.shared.log("LEARNING: recordManualApply for '\(token)' -> \(hyp.rawValue)")
                             await UserDictionary.shared.recordManualApply(token: token, hypothesis: hyp.rawValue, convertedText: finalAlt.text, bundleId: bundleId)
                         }
                     }
                 } else {
                     // Manual trigger
                     if finalIndex != 0 {
                         // 3. Learn from Manual Correction (ManualApply)
                         if let hyp = finalAlt.hypothesis {
                             DecisionLogger.shared.log("LEARNING: recordManualApply (manual) for '\(token)' -> \(hyp.rawValue)")
                             await UserDictionary.shared.recordManualApply(token: token, hypothesis: hyp.rawValue, convertedText: finalAlt.text, bundleId: bundleId)
                         }
                     } else {
                         DecisionLogger.shared.log("LEARNING: manual trigger but finalIndex=0, no learning")
                     }
                 }
             }
        }
        cyclingState = nil
    }
    
    /// Reset sentence-level state (called on sentence boundary like . ! ? or long pause)
    func resetSentence() {
        sentenceDominantLanguage = nil
        sentenceWordCount = 0
        pendingWord = nil
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
        if history.count > ThresholdsConfig.shared.correction.historyMaxSize {
            history.removeLast()
        }
        
        // Also update shared HistoryManager for UI
        Task { @MainActor in
            HistoryManager.shared.add(original: original, corrected: corrected, from: from, to: to)
        }
    }
}
