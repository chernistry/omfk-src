import Foundation
import os.log

/// Orchestrates language detection by routing requests through Fast (N-gram) and Standard (Ensemble) paths
/// based on confidence thresholds.
actor ConfidenceRouter {
    private let ensemble: LanguageEnsemble
    // N-gram detectors are also loaded inside Ensemble, but for the "Fast Path" 
    // we might want direct access or just rely on Ensemble's underlying models.
    // For V1, we'll route everything through Ensemble but check its confidence 
    // to decide whether to stop or proceed to deeper analysis (if we had a separate deep model).
    // Actually, per spec, Fast Path should be N-gram only. 
    // To do this cleanly without duplicating model loading, we can expose N-gram scoring from Ensemble 
    // or instantiate lightweight checkers here.
    // simpler approach for now: The Ensemble ALREADY computes N-gram scores. 
    // We can refactor Ensemble to separate the signals, or just use Ensemble for everything 
    // but check "Fast Path" criteria on the result.
    // BETTER APPROACH: Let ConfidenceRouter own the components.
    // But refactoring Ensemble completely is risky. 
    // HYBRID APPROACH: Router wraps Ensemble. 
    // "Fast Path" logic: If text length >= 4 and N-gram check (via static lightweight instance or efficient call) is high confidence.
    
    // For this implementation, we will trust the plan:
    // 1. Fast Path: N-gram only.
    // 2. Standard Path: Ensemble.
    
    private var ruModel: NgramLanguageModel?
    private var enModel: NgramLanguageModel?
    private var heModel: NgramLanguageModel?
    private let coreML: CoreMLLayoutClassifier
    private let wordValidator: WordValidator
    private var unigramCache: [Language: WordFrequencyModel] = [:]
    
    private let logger = Logger.detection
    private let settings: SettingsManager
    
    init(settings: SettingsManager) {
        self.settings = settings
        let validator = HybridWordValidator()
        self.wordValidator = validator
        self.ensemble = LanguageEnsemble(wordValidator: validator)
        // We load models separately for the Fast Path to ensure independence
        self.ruModel = try? NgramLanguageModel.loadLanguage("ru")
        self.enModel = try? NgramLanguageModel.loadLanguage("en")
        self.heModel = try? NgramLanguageModel.loadLanguage("he")
        self.coreML = CoreMLLayoutClassifier()
    }
    
    /// Main entry point for detection
    /// 
    /// NEW LOGIC (v2):
    /// - N-gram/Ensemble detect the SCRIPT of the text (Cyrillic -> "Russian").
    /// - CoreML detects LAYOUT MISMATCH ("this Cyrillic is gibberish Russian, but valid Hebrew from RU layout").
    /// - We ALWAYS invoke CoreML to check for `_from_` hypotheses, even if Fast/Standard is confident.
    func route(token: String, context: DetectorContext) async -> LanguageDecision {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
             let duration = CFAbsoluteTimeGetCurrent() - startTime
             if duration > 0.05 {
                 logger.warning("⚠️ Slow detection: \(String(format: "%.1f", duration * 1000))ms for \(DecisionLogger.tokenSummary(token), privacy: .public)")
             }
        }

        let activeLayouts = await settings.activeLayouts

        // -- STEP 0: Score-based decision (layout + language via conversions + n-grams + lexicon) --
        // This is deterministic and fixes cases where CoreML/NL miss the layout mismatch.
        if let scored = scoredDecision(token: token, activeLayouts: activeLayouts) {
            let stdThreshold = await settings.standardPathThreshold
            if scored.confidence >= stdThreshold {
                DecisionLogger.shared.logDecision(token: token, path: "SCORE", result: scored)
                return scored
            }
        }
        
        // -- STEP 1: Get a baseline decision via Fast or Standard path --
        var baselineDecision: LanguageDecision?
        var baselinePath = "STANDARD"
        
        // 1a. FAST PATH: N-gram Only
        if token.count >= 4 {
            if let fastDecision = checkFastPath(token) {
                let threshold = await settings.fastPathThreshold
                if fastDecision.confidence >= threshold {
                    logger.info("🚀 Fast Path (N-gram) candidate: \(fastDecision.language.rawValue, privacy: .public) (conf: \(fastDecision.confidence))")
                    baselineDecision = fastDecision
                    baselinePath = "FAST"
                }
            }
        }
        
        // 1b. STANDARD PATH: Ensemble (if Fast Path didn't produce high-confidence result)
        if baselineDecision == nil {
            let ensembleContext = EnsembleContext(lastLanguage: context.lastLanguage, activeLayouts: activeLayouts)
            let decision = await ensemble.classify(token, context: ensembleContext)
            let stdThreshold = await settings.standardPathThreshold
            if decision.confidence >= stdThreshold {
                logger.info("🛡️ Standard Path (Ensemble) candidate: \(decision.language.rawValue, privacy: .public) (conf: \(decision.confidence))")
                baselineDecision = decision
                baselinePath = "STANDARD"
            } else {
                // Even low confidence is better than nothing for fallback
                baselineDecision = decision
                baselinePath = "FALLBACK"
            }
        }
        
        guard let baseline = baselineDecision else {
            // Shouldn't happen, but be safe
            let fallback = LanguageDecision(language: .english, layoutHypothesis: .en, confidence: 0.5, scores: [:])
            DecisionLogger.shared.logDecision(token: token, path: "ERROR", result: fallback)
            return fallback
        }

        // If baseline already suggests a correction, validate it before involving CoreML.
        if baseline.layoutHypothesis.rawValue.contains("_from_") {
            if let validated = validateCorrection(
                token: token,
                hypothesis: baseline.layoutHypothesis,
                confidence: baseline.confidence,
                activeLayouts: activeLayouts
            ) {
                DecisionLogger.shared.logDecision(token: token, path: "BASELINE_CORRECTION", result: validated)
                return validated
            }
        }

        // -- STEP 2: ALWAYS invoke CoreML to check for layout mismatch --
        // CoreML can detect "_from_" hypotheses that contradict the baseline.
        logger.info("🧠 Deep Path (CoreML) checking for layout mismatch: \(DecisionLogger.tokenSummary(token), privacy: .public)")
        
        if let (deepHypothesis, deepConf) = coreML.predict(token) {
            logger.info("🧠 Deep Path result: \(deepHypothesis.rawValue, privacy: .public) (conf: \(deepConf))")
            
            let isCorrection = deepHypothesis.rawValue.contains("_from_")
            
            if isCorrection {
                // CoreML thinks this is a layout mismatch (e.g. "en_from_ru").
                // VALIDATION: Before accepting, convert the text and verify the result
                // is actually valid in the target language using N-gram scoring.
                // Allow lower CoreML confidence when conversion validation is strong.
                let correctionThreshold = 0.45
                if deepConf > correctionThreshold {
                    // Determine source and target layouts
                    let sourceLayout: Language
                    let targetLanguage = deepHypothesis.targetLanguage
                    
                    switch deepHypothesis {
                    case .ruFromEnLayout, .heFromEnLayout: sourceLayout = .english
                    case .enFromRuLayout, .heFromRuLayout: sourceLayout = .russian
                    case .enFromHeLayout, .ruFromHeLayout: sourceLayout = .hebrew
                    default: sourceLayout = .english
                    }
                    
                    let sourceScore = scoreWithNgram(token, language: sourceLayout)
                    let sourceNorm = scoreWithNgramNormalized(token, language: sourceLayout)

                    func isShortLetters(_ text: String) -> Bool {
                        text.filter { $0.isLetter }.count <= 3
                    }

                    let sourceWordConfidence = wordValidator.confidence(for: token, language: sourceLayout)

                    func isValidConversion(_ converted: String) -> Bool {
                        let targetWordConfidence = wordValidator.confidence(for: converted, language: targetLanguage)
                        if isShortLetters(converted) {
                            DecisionLogger.shared.log("SHORT_CHECK: \(converted) wordConf=\(String(format: "%.2f", targetWordConfidence)) need>=0.95")
                            return targetWordConfidence >= 0.95
                        }

                        let targetNorm = scoreWithNgramNormalized(converted, language: targetLanguage)

                        DecisionLogger.shared.log("VALID_CHECK: \(converted) wordConf=\(String(format: "%.2f", targetWordConfidence)) srcWordConf=\(String(format: "%.2f", sourceWordConfidence)) tgtNorm=\(String(format: "%.2f", targetNorm)) srcNorm=\(String(format: "%.2f", sourceNorm))")

                        // Prefer real words/phrases in the target language when it is notably stronger
                        // than the source according to word validation / n-gram.
                        if targetWordConfidence >= 0.80 && targetWordConfidence >= sourceWordConfidence + 0.20 {
                            return true
                        }

                        return targetNorm >= 0.75 && targetNorm >= sourceNorm + 0.15
                    }

                    // Prefer conversion using the user-selected/detected active layouts first.
                    if let primary = LayoutMapper.shared.convertBest(token, from: sourceLayout, to: targetLanguage, activeLayouts: activeLayouts),
                       primary != token,
                       isValidConversion(primary) {
                        let deepResult = LanguageDecision(
                            language: targetLanguage,
                            layoutHypothesis: deepHypothesis,
                            confidence: max(deepConf, 0.90),
                            scores: [:]
                        )
                        DecisionLogger.shared.log("VALIDATED_PRIMARY: \(token) → \(primary)")
                        DecisionLogger.shared.logDecision(token: token, path: "DEEP_CORRECTION", result: deepResult)
                        return deepResult
                    }

                    // Fall back to trying ALL source layout variants (handles unknown source variants).
                    let variants = LayoutMapper.shared.convertAllVariants(token, from: sourceLayout, to: targetLanguage, activeLayouts: activeLayouts)
                    var bestConversion: (converted: String, score: Double)? = nil

                    for (layoutId, converted) in variants {
                        let targetScore = scoreWithNgram(converted, language: targetLanguage)
                        let targetNorm = scoreWithNgramNormalized(converted, language: targetLanguage)
                        DecisionLogger.shared.log("VARIANT[\(layoutId)]: \(token) → \(converted) | src=\(String(format: "%.2f", sourceScore)) tgt=\(String(format: "%.2f", targetScore)) tgtN=\(String(format: "%.2f", targetNorm))")

                        if isValidConversion(converted) {
                            if bestConversion == nil || targetNorm > bestConversion!.score {
                                bestConversion = (converted, targetNorm)
                            }
                        }
                    }
                    
                    if bestConversion != nil {
                        let deepResult = LanguageDecision(
                            language: targetLanguage, 
                            layoutHypothesis: deepHypothesis,
                            confidence: max(deepConf, 0.85),
                            scores: [:] 
                        )
                        DecisionLogger.shared.logDecision(token: token, path: "DEEP_CORRECTION", result: deepResult)
                        return deepResult
                    } else {
                        let rejectedMsg = "REJECTED_VALIDATION: \(deepHypothesis.rawValue) | no valid conversion found from \(variants.count) variants"
                        DecisionLogger.shared.log(rejectedMsg)
                    }
                } else {
                    let rejectedMsg = "REJECTED_DEEP_CORRECTION: \(deepHypothesis.rawValue) (\(String(format: "%.2f", deepConf))) < \(correctionThreshold)"
                    DecisionLogger.shared.log(rejectedMsg)
                }
            } else {
                // CoreML just confirms the script (e.g. "ru" for Cyrillic).
                // Only prefer CoreML if it's more confident than baseline.
                if deepConf > baseline.confidence && deepConf > 0.7 {
                    let deepResult = LanguageDecision(
                        language: deepHypothesis.targetLanguage, 
                        layoutHypothesis: deepHypothesis,
                        confidence: deepConf,
                        scores: [:] 
                    )
                    DecisionLogger.shared.logDecision(token: token, path: "DEEP", result: deepResult)
                    return deepResult
                }
            }
        }
        
        // -- STEP 3: Fall back to baseline --
        // Heuristic correction: if the token looks like gibberish in its dominant script,
        // try layout conversions even when CoreML doesn't propose a `_from_` hypothesis.
        if let heuristic = heuristicCorrection(token: token, baseline: baseline, activeLayouts: activeLayouts) {
            DecisionLogger.shared.logDecision(token: token, path: "HEURISTIC", result: heuristic)
            return heuristic
        }

        DecisionLogger.shared.logDecision(token: token, path: baselinePath, result: baseline)
        return baseline
    }
    
    private func checkFastPath(_ text: String) -> LanguageDecision? {
        // Avoid Fast Path if script is mixed (fast path is only for "already-correct" text).
        guard let dominant = dominantScriptLanguage(text) else { return nil }
        if dominant == .hebrew { return nil }

        // Quick scoring against 3 languages
        let sRu = ruModel?.score(text) ?? -100
        let sEn = enModel?.score(text) ?? -100
        let sHe = heModel?.score(text) ?? -100
        
        // Convert log-probs to approximate confidence/probability
        // This is a simplified Softmax-like logic for 3 classes
        let scores = [sRu, sEn, sHe]
        let maxScore = scores.max() ?? -100
        
        // If max score is very low (garbage), ignore
        if maxScore < -8.0 { return nil }
        
        var bestLang: Language = .english
        var bestScore = sEn
        
        if sRu > bestScore { bestLang = .russian; bestScore = sRu }
        if sHe > bestScore { bestLang = .hebrew; bestScore = sHe }
        
        // Simple margin confidence
        // Find second best
        let sorted = scores.sorted(by: >)
        let margin = sorted[0] - sorted[1]
        
        // Heuristic mapping: margin 0.0 -> 0.5, margin 2.0 -> 0.9 approximately
        var confidence = min(1.0, 0.5 + Double(margin) * 0.2)

        // Only accept fast-path when the best language matches dominant script
        // AND the token looks like a real word/phrase in that language.
        if bestLang != dominant { return nil }
        let wordConf = wordValidator.confidence(for: text, language: bestLang)
        if wordConf < 0.80 {
            // Downweight and decline Fast Path; let Ensemble/CoreML handle it.
            confidence *= 0.5
            return nil
        }
        
        return LanguageDecision(
            language: bestLang,
            layoutHypothesis: bestLang.asHypothesis,
            confidence: confidence,
            scores: [
                .ru: Double(sRu),
                .en: Double(sEn),
                .he: Double(sHe)
            ]
        )
    }
    
    /// Score text against a specific language's N-gram model
    private func scoreWithNgram(_ text: String, language: Language) -> Double {
        let model: NgramLanguageModel?
        switch language {
        case .russian: model = ruModel
        case .english: model = enModel
        case .hebrew: model = heModel
        }
        return Double(model?.score(text) ?? -100.0)
    }

    private func scoreWithNgramNormalized(_ text: String, language: Language) -> Double {
        let model: NgramLanguageModel?
        switch language {
        case .russian: model = ruModel
        case .english: model = enModel
        case .hebrew: model = heModel
        }
        return model?.normalizedScore(text) ?? 0.0
    }

    private func unigramModel(for language: Language) -> WordFrequencyModel? {
        if let cached = unigramCache[language] { return cached }
        let code: String
        switch language {
        case .english: code = "en"
        case .russian: code = "ru"
        case .hebrew: code = "he"
        }
        guard let model = try? WordFrequencyModel.loadLanguage(code) else { return nil }
        unigramCache[language] = model
        return model
    }

    private func frequencyScore(_ text: String, language: Language) -> Double {
        guard let model = unigramModel(for: language) else { return 0.0 }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.0 }

        let words = trimmed
            .split(whereSeparator: { !$0.isLetter })
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return 0.0 }
        let sum = words.reduce(0.0) { $0 + model.score($1) }
        return sum / Double(words.count)
    }

    private func dominantScriptLanguage(_ text: String) -> Language? {
        var latin = 0
        var cyr = 0
        var heb = 0

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0041...0x005A, 0x0061...0x007A:
                latin += 1
            case 0x0400...0x04FF:
                cyr += 1
            case 0x0590...0x05FF:
                heb += 1
            default:
                continue
            }
        }

        let total = latin + cyr + heb
        guard total > 0 else { return nil }

        let best = max(latin, cyr, heb)
        if Double(best) / Double(total) < 0.85 { return nil }

        if best == cyr { return .russian }
        if best == heb { return .hebrew }
        return .english
    }

    private func validateCorrection(
        token: String,
        hypothesis: LanguageHypothesis,
        confidence: Double,
        activeLayouts: [String: String]
    ) -> LanguageDecision? {
        guard hypothesis.rawValue.contains("_from_") else { return nil }

        let targetLanguage = hypothesis.targetLanguage
        let sourceLayout: Language
        switch hypothesis {
        case .ruFromEnLayout, .heFromEnLayout: sourceLayout = .english
        case .enFromRuLayout, .heFromRuLayout: sourceLayout = .russian
        case .enFromHeLayout, .ruFromHeLayout: sourceLayout = .hebrew
        default: sourceLayout = .english
        }

        guard let converted = LayoutMapper.shared.convertBest(token, from: sourceLayout, to: targetLanguage, activeLayouts: activeLayouts),
              converted != token else { return nil }

        let sourceWord = wordValidator.confidence(for: token, language: sourceLayout)
        let targetWord = wordValidator.confidence(for: converted, language: targetLanguage)

        let sourceNorm = scoreWithNgramNormalized(token, language: sourceLayout)
        let targetNorm = scoreWithNgramNormalized(converted, language: targetLanguage)

        let sourceFreq = frequencyScore(token, language: sourceLayout)
        let targetFreq = frequencyScore(converted, language: targetLanguage)

        let letterCount = token.filter { $0.isLetter }.count
        let isShort = letterCount <= 3

        // Strong accept: target looks like real text and source looks like gibberish.
        if targetWord >= 0.80 && (targetWord >= sourceWord + 0.20 || targetFreq >= sourceFreq + 0.20) {
            return LanguageDecision(language: targetLanguage, layoutHypothesis: hypothesis, confidence: max(confidence, 0.85), scores: [:])
        }

        // For very short tokens, require a strong unigram-frequency improvement to avoid false positives
        // from permissive spellcheckers on 2-letter strings.
        if isShort, targetFreq >= 0.45, targetFreq >= sourceFreq + 0.25 {
            return LanguageDecision(language: targetLanguage, layoutHypothesis: hypothesis, confidence: max(confidence, 0.85), scores: [:])
        }

        // Fallback: accept when n-gram quality improves significantly (normalized per-language).
        if targetNorm >= 0.75 && targetNorm >= sourceNorm + 0.15 && (targetFreq >= sourceFreq || targetWord >= 0.60) {
            return LanguageDecision(language: targetLanguage, layoutHypothesis: hypothesis, confidence: max(confidence, 0.80), scores: [:])
        }

        return nil
    }

    private func heuristicCorrection(
        token: String,
        baseline: LanguageDecision,
        activeLayouts: [String: String]
    ) -> LanguageDecision? {
        guard let dominant = dominantScriptLanguage(token) else { return nil }

        // If the token already looks like a valid word/phrase in its dominant script,
        // don't attempt layout correction (avoid false positives).
        if wordValidator.confidence(for: token, language: dominant) >= 0.80 {
            return nil
        }

        let candidates: [LanguageHypothesis]
        switch dominant {
        case .english:
            candidates = [.ruFromEnLayout, .heFromEnLayout]
        case .russian:
            candidates = [.enFromRuLayout, .heFromRuLayout]
        case .hebrew:
            candidates = [.enFromHeLayout, .ruFromHeLayout]
        }

        let baseConf = max(0.75, baseline.confidence)

        for hyp in candidates {
            if let validated = validateCorrection(token: token, hypothesis: hyp, confidence: baseConf, activeLayouts: activeLayouts) {
                return validated
            }
        }

        return nil
    }

    private func scoredDecision(token: String, activeLayouts: [String: String]) -> LanguageDecision? {
        func quality(_ text: String, lang: Language) -> Double {
            let letters = text.filter { $0.isLetter }
            let isShort = letters.count <= 3

            let w = wordValidator.confidence(for: text, language: lang)
            let n = isShort ? 0.0 : scoreWithNgramNormalized(text, language: lang)
            let f = frequencyScore(text, language: lang)

            return (isShort ? 1.6 : 1.2) * w + (isShort ? 1.6 : 1.0) * f + (isShort ? 0.0 : 0.6) * n
        }

        // Best "as-is" quality across languages.
        let asIsRu = quality(token, lang: .russian)
        let asIsEn = quality(token, lang: .english)
        let asIsHe = quality(token, lang: .hebrew)
        let bestAsIs = max(asIsRu, asIsEn, asIsHe)

        struct Candidate {
            let hypothesis: LanguageHypothesis
            let target: Language
            let converted: String
            let targetWord: Double
            let q: Double
        }

        let mapped: [(LanguageHypothesis, Language, Language)] = [
            (.ruFromEnLayout, .english, .russian),
            (.heFromEnLayout, .english, .hebrew),
            (.enFromRuLayout, .russian, .english),
            (.heFromRuLayout, .russian, .hebrew),
            (.enFromHeLayout, .hebrew, .english),
            (.ruFromHeLayout, .hebrew, .russian),
        ]

        var best: Candidate? = nil
        for (hyp, source, target) in mapped {
            guard let converted = LayoutMapper.shared.convertBest(token, from: source, to: target, activeLayouts: activeLayouts),
                  converted != token else { continue }
            let targetWord = wordValidator.confidence(for: converted, language: target)
            let q = quality(converted, lang: target) - 0.05 // small bias against corrections
            let cand = Candidate(hypothesis: hyp, target: target, converted: converted, targetWord: targetWord, q: q)
            if best == nil || cand.q > best!.q { best = cand }
        }

        guard let best else { return nil }

        // Only accept if the best mapped hypothesis is substantially better than any as-is option.
        let letterCount = token.filter { $0.isLetter }.count
        let requiredMargin = letterCount <= 3 ? 0.25 : 0.70
        guard best.q >= bestAsIs + requiredMargin else { return nil }
        guard best.targetWord >= 0.80 else { return nil }

        return LanguageDecision(language: best.target, layoutHypothesis: best.hypothesis, confidence: 0.95, scores: [:])
    }
}

// Helper types
extension Language {
    var asHypothesis: LanguageHypothesis {
        switch self {
        case .russian: return .ru
        case .english: return .en
        case .hebrew: return .he
        }
    }
}

/// Context passed to the router
struct DetectorContext: Sendable {
    let lastLanguage: Language?
}

/// Unified decision type (aliasing existing one or wrapping it)
/// For now, we reuse LanguageDecision from LanguageEnsemble.swift
// Note: LanguageDecision is defined there.
