import Foundation
import os.log

enum DetectionMode: Sendable {
    /// Used for background/automatic corrections. Prefer precision; avoid risky corrections.
    case automatic
    /// Used for user-invoked hotkey corrections. Prefer recall; ambiguity is acceptable.
    case manual
}

/// Known single-letter Russian prepositions/conjunctions that should always be valid conversions
private let knownRussianPrepositions: Set<String> = ["а", "в", "и", "к", "о", "с", "у", "я"]

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
    private let builtinValidator: BuiltinWordValidator = BuiltinWordValidator()
    
    private let logger = Logger.detection
    private let settings: SettingsManager
    
    init(settings: SettingsManager) {
        self.settings = settings
        self.wordValidator = HybridWordValidator()
        self.ensemble = LanguageEnsemble()
        self.ruModel = try? NgramLanguageModel.loadLanguage("ru")
        self.enModel = try? NgramLanguageModel.loadLanguage("en")
        self.heModel = try? NgramLanguageModel.loadLanguage("he")
        self.coreML = CoreMLLayoutClassifier()
    }
    
    private let languageData = LanguageDataConfig.shared
    private let thresholds = ThresholdsConfig.shared
    
    /// Main entry point for detection
    /// 
    /// NEW LOGIC (v2):
    /// - N-gram/Ensemble detect the SCRIPT of the text (Cyrillic -> "Russian").
    /// - CoreML detects LAYOUT MISMATCH ("this Cyrillic is gibberish Russian, but valid Hebrew from RU layout").
    /// - We ALWAYS invoke CoreML to check for `_from_` hypotheses, even if Fast/Standard is confident.
    func route(token: String, context: DetectorContext, mode: DetectionMode = .automatic) async -> LanguageDecision {
        // NEW: User Dictionary Lookup
        if let rule = await UserDictionary.shared.lookup(token) {
            switch rule.action {
            case .keepAsIs:
                if mode == .manual {
                     // Unlearning Flow A: User forces correction on a "keep as-is" token
                     await UserDictionary.shared.recordOverride(token: token)
                     // Proceed with detection (ignore the rule)
                } else {
                     // Automatic mode: Respect the rule (do NOT correct)
                     let dominant = dominantScriptLanguage(token)
                     let lang = dominant ?? .english
                     let hyp: LanguageHypothesis = (lang == .russian) ? .ru : ((lang == .hebrew) ? .he : .en)
                     
                     let decision = LanguageDecision(language: lang, layoutHypothesis: hyp, confidence: 1.0, scores: [:])
                     DecisionLogger.shared.logDecision(token: token, path: "USER_DICT_KEEP", result: decision)
                     return decision
                }
            case .preferHypothesis(let hypStr):
                 // Check if we can map string to hypothesis
                 if let hyp = LanguageHypothesis(rawValue: hypStr) {
                      // User explicitly wants this conversion - apply it without strict validation
                      let activeLayouts = await settings.activeLayouts
                      let target = hyp.targetLanguage
                      
                      // Determine source language from hypothesis
                      let source: Language
                      switch hyp {
                      case .ruFromEnLayout, .heFromEnLayout: source = .english
                      case .enFromRuLayout, .heFromRuLayout: source = .russian
                      case .enFromHeLayout, .ruFromHeLayout: source = .hebrew
                      default: source = .english // as-is hypotheses don't need conversion
                      }
                      
                      // Try to convert using the preferred hypothesis
                      if let converted = LayoutMapper.shared.convertBest(token, from: source, to: target, activeLayouts: activeLayouts),
                         converted != token {
                           let decision = LanguageDecision(
                               language: target,
                               layoutHypothesis: hyp,
                               confidence: 1.0,
                               scores: [:]
                           )
                           DecisionLogger.shared.logDecision(token: token, path: "USER_DICT_PREFER", result: decision)
                           return decision
                      }
                 }
            case .none:
                 break
            default:
                 break
            }
        }

        // Technical token guard (automatic mode):
        // Prevent accidental conversion of file paths, UUIDs, semver, etc.
        if mode == .automatic, isTechnicalToken(token) {
            let decision = LanguageDecision(language: .english, layoutHypothesis: .en, confidence: 1.0, scores: [:])
            DecisionLogger.shared.logDecision(token: token, path: "TECHNICAL_KEEP", result: decision)
            return decision
        }

        // Whitelist check - don't convert common words/slang
        if let lang = languageData.whitelistedLanguage(token) {
            let hyp: LanguageHypothesis = lang == .english ? .en : (lang == .russian ? .ru : .he)
            let decision = LanguageDecision(language: lang, layoutHypothesis: hyp, confidence: 1.0, scores: [:])
            DecisionLogger.shared.logDecision(token: token, path: "WHITELIST", result: decision)
            return decision
        }

        // Strong-script sanity (automatic mode):
        // If the token is dominantly Cyrillic and looks like a valid Russian word/phrase,
        // do NOT attempt layout corrections away from Russian. This prevents false positives like
        // "люблю" being treated as `en_from_ru` and entering an auto-reject learning loop.
        if mode == .automatic, dominantScriptLanguage(token) == .russian {
            let ruWord = wordValidator.confidence(for: token, language: .russian)
            if ruWord >= thresholds.sourceWordConfMax {
                let decision = LanguageDecision(language: .russian, layoutHypothesis: .ru, confidence: 1.0, scores: [:])
                DecisionLogger.shared.logDecision(token: token, path: "SCRIPT_LOCK_RU", result: decision)
                return decision
            }
        }
        
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
        if let scored = scoredDecision(token: token, activeLayouts: activeLayouts, mode: mode) {
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
            let fallback = LanguageDecision(language: .english, layoutHypothesis: .en, confidence: thresholds.fallbackConfidence, scores: [:])
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
                if deepConf > thresholds.correctionThreshold {
                    // Determine source and target layouts
                    let sourceLayout: Language
                    let targetLanguage = deepHypothesis.targetLanguage
                    
                    switch deepHypothesis {
                    case .ruFromEnLayout, .heFromEnLayout: sourceLayout = .english
                    case .enFromRuLayout, .heFromRuLayout: sourceLayout = .russian
                    case .enFromHeLayout, .ruFromHeLayout: sourceLayout = .hebrew
                    default: sourceLayout = .english
                    }

                    // Reject corrections where the token's dominant script doesn't match the hypothesis source.
                    if let dominant = dominantScriptLanguage(token), dominant != sourceLayout {
                        let rejectedMsg = "REJECTED_SCRIPT: \(deepHypothesis.rawValue) | dominant=\(dominant.rawValue) source=\(sourceLayout.rawValue)"
                        DecisionLogger.shared.log(rejectedMsg)
                        DecisionLogger.shared.logDecision(token: token, path: "DEEP", result: baseline)
                        return baseline
                    }
                    
                    let sourceScore = scoreWithNgram(token, language: sourceLayout)
                    let sourceNorm = scoreWithNgramNormalized(token, language: sourceLayout)

                    let sourceWordConfidence = wordValidator.confidence(for: token, language: sourceLayout)
                    let sourceFreq = frequencyScore(token, language: sourceLayout)

                    func isValidConversion(_ converted: String, targetLanguage: Language) -> Bool {
                        // Known Russian prepositions are always valid
                        if targetLanguage == .russian && knownRussianPrepositions.contains(converted.lowercased()) {
                            return true
                        }
                        
                        let targetWordConfidence = wordValidator.confidence(for: converted, language: targetLanguage)
                        let targetFreq = frequencyScore(converted, language: targetLanguage)
                        let shortLetters = converted.filter { $0.isLetter }.count <= 3
                        if shortLetters {
                            return targetWordConfidence >= thresholds.targetWordMin && targetFreq >= sourceFreq + thresholds.targetFreqMargin
                        }

                        let targetNorm = scoreWithNgramNormalized(converted, language: targetLanguage)

                        DecisionLogger.shared.log("VALID_CHECK: \(converted) wordConf=\(String(format: "%.2f", targetWordConfidence)) srcWordConf=\(String(format: "%.2f", sourceWordConfidence)) tgtNorm=\(String(format: "%.2f", targetNorm)) srcNorm=\(String(format: "%.2f", sourceNorm))")

                        if targetWordConfidence >= thresholds.targetWordMin && targetWordConfidence >= sourceWordConfidence + thresholds.targetWordMargin {
                            return true
                        }

                        if targetFreq >= sourceFreq + thresholds.targetFreqMargin && targetWordConfidence >= thresholds.shortWordFreqMin {
                            return true
                        }

                        return targetNorm >= thresholds.targetNormMin && targetNorm >= sourceNorm + thresholds.targetNormMargin && (targetFreq >= sourceFreq || targetWordConfidence >= thresholds.shortWordFreqMin)
                    }

                    func correctionHypotheses(for sourceLayout: Language) -> [LanguageHypothesis] {
                        switch sourceLayout {
                        case .english: return [.ruFromEnLayout, .heFromEnLayout]
                        case .russian: return [.enFromRuLayout, .heFromRuLayout]
                        case .hebrew: return [.enFromHeLayout, .ruFromHeLayout]
                        }
                    }

                    struct ValidatedCandidate {
                        let hypothesis: LanguageHypothesis
                        let targetLanguage: Language
                        let converted: String
                        let quality: Double
                    }

                    func bestValidatedCandidate(hypothesis: LanguageHypothesis) -> ValidatedCandidate? {
                        let src: Language
                        let tgt = hypothesis.targetLanguage
                        switch hypothesis {
                        case .ruFromEnLayout, .heFromEnLayout: src = .english
                        case .enFromRuLayout, .heFromRuLayout: src = .russian
                        case .enFromHeLayout, .ruFromHeLayout: src = .hebrew
                        default: return nil
                        }

                        guard let dominant = dominantScriptLanguage(token), dominant == src else { return nil }

                        func consider(_ converted: String) -> ValidatedCandidate? {
                            guard converted != token else { return nil }
                            guard isValidConversion(converted, targetLanguage: tgt) else { return nil }
                            return ValidatedCandidate(
                                hypothesis: hypothesis,
                                targetLanguage: tgt,
                                converted: converted,
                                quality: qualityScore(converted, lang: tgt) + correctionPriorBonus(for: hypothesis)
                            )
                        }

                        // Always check ALL layout variants and pick the best one
                        // This handles cases like Hebrew QWERTY user typing Mac Hebrew patterns
                        let variants = LayoutMapper.shared.convertAllVariants(token, from: src, to: tgt, activeLayouts: activeLayouts)
                        var best: ValidatedCandidate? = nil
                        for (_, converted) in variants {
                            if let cand = consider(converted), (best == nil || cand.quality > best!.quality) {
                                best = cand
                            }
                        }
                        return best
                    }

                    // Cross-check competing correction hypotheses for the same source script.
                    // This reduces cases like RU→EN being mistaken as RU→HE when both conversions look plausible.
                    let correctionCandidates = correctionHypotheses(for: sourceLayout)
                    var validated: [ValidatedCandidate] = []
                    validated.reserveCapacity(correctionCandidates.count)
                    for hyp in correctionCandidates {
                        if let cand = bestValidatedCandidate(hypothesis: hyp) { validated.append(cand) }
                    }

                    if !validated.isEmpty {
                        let bestOverall = validated.max(by: { $0.quality < $1.quality })!
                        let bestIsModel = bestOverall.hypothesis == deepHypothesis

                        // Only override CoreML when the alternative is clearly better.
                        if !bestIsModel {
                            if let modelCand = validated.first(where: { $0.hypothesis == deepHypothesis }) {
                                if bestOverall.quality < modelCand.quality + 0.12 {
                                    // Not a strong enough reason to override; keep CoreML's choice.
                                    validated = [modelCand]
                                }
                            }
                        }

                        let chosen = validated.max(by: { $0.quality < $1.quality })!
                        let chosenConf = max(deepConf, 0.90)
                        let deepResult = LanguageDecision(
                            language: chosen.targetLanguage,
                            layoutHypothesis: chosen.hypothesis,
                            confidence: chosenConf,
                            scores: [:]
                        )
                        DecisionLogger.shared.log("DEEP_BEST: \(chosen.hypothesis.rawValue) via \(chosen.converted)")
                        DecisionLogger.shared.logDecision(token: token, path: "DEEP_CORRECTION", result: deepResult)
                        return deepResult
                    }

                    // Prefer conversion using the user-selected/detected active layouts first.
                    if let primary = LayoutMapper.shared.convertBest(token, from: sourceLayout, to: targetLanguage, activeLayouts: activeLayouts),
                       primary != token,
                       isValidConversion(primary, targetLanguage: targetLanguage) {
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

                        if isValidConversion(converted, targetLanguage: targetLanguage) {
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
                    let rejectedMsg = "REJECTED_DEEP_CORRECTION: \(deepHypothesis.rawValue) (\(String(format: "%.2f", deepConf))) < \(thresholds.correctionThreshold)"
                    DecisionLogger.shared.log(rejectedMsg)
                }
            } else {
                // CoreML just confirms the script (e.g. "ru" for Cyrillic).
                // Only prefer CoreML if it's more confident than baseline.
                if deepConf > baseline.confidence && deepConf > thresholds.deepConfidenceMin {
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

        // Script gate: if the token clearly belongs to a different script than the hypothesis source,
        // reject to avoid false positives (e.g. valid English with punctuation being "corrected" as en_from_he).
        if let dominant = dominantScriptLanguage(token), dominant != sourceLayout {
            return nil
        }

        guard let converted = LayoutMapper.shared.convertBest(token, from: sourceLayout, to: targetLanguage, activeLayouts: activeLayouts),
              converted != token else { return nil }

        // Known Russian prepositions are always valid
        if targetLanguage == .russian && knownRussianPrepositions.contains(converted.lowercased()) {
            return LanguageDecision(language: targetLanguage, layoutHypothesis: hypothesis, confidence: max(confidence, 0.90), scores: [:])
        }

        let sourceWord = wordValidator.confidence(for: token, language: sourceLayout)
        let targetWord = wordValidator.confidence(for: converted, language: targetLanguage)

        let sourceNorm = scoreWithNgramNormalized(token, language: sourceLayout)
        let targetNorm = scoreWithNgramNormalized(converted, language: targetLanguage)

        let sourceFreq = frequencyScore(token, language: sourceLayout)
        let targetFreq = frequencyScore(converted, language: targetLanguage)

        let letterCount = token.filter { $0.isLetter }.count
        let isShort = letterCount <= 3

        let sourceBuiltin = builtinValidator.confidence(for: token, language: sourceLayout)
        let targetBuiltin = builtinValidator.confidence(for: converted, language: targetLanguage)

        // Strong accept: target looks like real text and source looks like gibberish.
        if targetBuiltin >= 0.99 && sourceBuiltin <= 0.01 {
            return LanguageDecision(language: targetLanguage, layoutHypothesis: hypothesis, confidence: max(confidence, 0.90), scores: [:])
        }

        if targetWord >= thresholds.targetWordMin && (targetWord >= sourceWord + thresholds.targetWordMargin || targetFreq >= sourceFreq + thresholds.targetWordMargin) {
            return LanguageDecision(language: targetLanguage, layoutHypothesis: hypothesis, confidence: max(confidence, 0.85), scores: [:])
        }

        // For very short tokens, require a strong unigram-frequency improvement
        if isShort, targetFreq >= 0.45, targetFreq >= sourceFreq + thresholds.targetFreqMargin {
            return LanguageDecision(language: targetLanguage, layoutHypothesis: hypothesis, confidence: max(confidence, 0.85), scores: [:])
        }

        // Fallback: accept when n-gram quality improves significantly
        if targetNorm >= thresholds.targetNormMin && targetNorm >= sourceNorm + thresholds.targetNormMargin && (targetFreq >= sourceFreq || targetWord >= thresholds.shortWordFreqMin) {
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
        if wordValidator.confidence(for: token, language: dominant) >= thresholds.sourceWordConfMax {
            return nil
        }

        let candidates: [LanguageHypothesis]
        switch dominant {
        case .english:
            candidates = [.ruFromEnLayout, .heFromEnLayout]
        case .russian:
            // Prioritize en over he - typing Hebrew on Russian layout is very rare
            candidates = [.enFromRuLayout]
        case .hebrew:
            // Prioritize en over ru - typing Russian on Hebrew layout is rare
            candidates = [.enFromHeLayout, .ruFromHeLayout]
        }

        let baseConf = max(thresholds.baseConfMin, baseline.confidence)

        for hyp in candidates {
            if let validated = validateCorrection(token: token, hypothesis: hyp, confidence: baseConf, activeLayouts: activeLayouts) {
                return validated
            }
        }

        return nil
    }

    private func qualityScore(_ text: String, lang: Language) -> Double {
        let letters = text.filter { $0.isLetter }
        let isShort = letters.count <= 3

        let w = wordValidator.confidence(for: text, language: lang)
        let n = isShort ? 0.0 : scoreWithNgramNormalized(text, language: lang)
        let f = frequencyScore(text, language: lang)

        return (isShort ? 1.6 : 1.2) * w + (isShort ? 1.6 : 1.0) * f + (isShort ? 0.0 : 0.6) * n
    }

    private func correctionPriorBonus(for hypothesis: LanguageHypothesis) -> Double {
        // Priors to reduce rare/undesired corrections in ambiguous cases.
        // These are deliberately small; they shouldn't override strong evidence.
        switch hypothesis {
        case .heFromRuLayout:
            return -0.28 // RU→HE is rarer than RU→EN for Cyrillic gibberish.
        case .ruFromHeLayout:
            return 0.06 // Encourage HE→RU when Russian looks strong.
        case .enFromHeLayout:
            return 0.08 // Hebrew-QWERTY collisions: prefer EN.
        default:
            return 0.0
        }
    }

    private func endsWithHebrewNonFinalForm(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        // Final forms: ך ם ן ף ץ. If a word ends with the non-final form (כ מ נ פ צ),
        // it's often an artefact of layout mapping.
        return ["כ", "מ", "נ", "פ", "צ"].contains(String(last))
    }

    private func scoredDecision(token: String, activeLayouts: [String: String], mode: DetectionMode) -> LanguageDecision? {

        // Best "as-is" quality across languages.
        let asIsRu = qualityScore(token, lang: .russian)
        let asIsEn = qualityScore(token, lang: .english)
        let asIsHe = qualityScore(token, lang: .hebrew)
        let bestAsIs = max(asIsRu, asIsEn, asIsHe)

        struct Candidate {
            let hypothesis: LanguageHypothesis
            let target: Language
            let converted: String
            let targetWord: Double
            let targetFreq: Double
            let q: Double
            let isWhitelisted: Bool
        }

        let mapped: [(LanguageHypothesis, Language, Language)] = [
            (.ruFromEnLayout, .english, .russian),
            (.heFromEnLayout, .english, .hebrew),
            (.enFromRuLayout, .russian, .english),
            (.heFromRuLayout, .russian, .hebrew),
            (.enFromHeLayout, .hebrew, .english),
            (.ruFromHeLayout, .hebrew, .russian),
        ]

        let dominant = dominantScriptLanguage(token)

        var best: Candidate? = nil
        for (hyp, source, target) in mapped {
            // Script gate: don't consider hypotheses whose source script doesn't match the token.
            // This prevents false positives for already-correct text with punctuation (e.g. "how,what").
            if let dominant, dominant != source { continue }

            // Try ALL target layout variants to handle cases like Hebrew QWERTY user typing Mac Hebrew patterns
            let variants = LayoutMapper.shared.convertAllVariants(token, from: source, to: target, activeLayouts: activeLayouts)
            for (_, converted) in variants {
                guard converted != token else { continue }
                let targetWord = wordValidator.confidence(for: converted, language: target)
                let targetFreq = frequencyScore(converted, language: target)
                let q = qualityScore(converted, lang: target) - 0.05 + correctionPriorBonus(for: hyp) // small bias against corrections
                let whitelisted = languageData.isWhitelisted(converted, language: target)
                let sourceBuiltin = builtinValidator.confidence(for: token, language: source)
                let targetBuiltin = builtinValidator.confidence(for: converted, language: target)
                if targetBuiltin >= 0.99 && sourceBuiltin <= 0.01 {
                    return LanguageDecision(language: target, layoutHypothesis: hyp, confidence: 0.95, scores: [:])
                }
                let cand = Candidate(hypothesis: hyp, target: target, converted: converted, targetWord: targetWord, targetFreq: targetFreq, q: q, isWhitelisted: whitelisted)
                if best == nil || cand.q > best!.q { best = cand }
            }
        }

        guard let best else { return nil }

        // Collision handler for Hebrew-QWERTY: the typed Hebrew token can be a valid Hebrew word,
        // but the mapped EN/RU candidate is also a very plausible, high-frequency word.
        if dominant == .hebrew, best.hypothesis == .enFromHeLayout || best.hypothesis == .ruFromHeLayout {
            let srcWord = wordValidator.confidence(for: token, language: .hebrew)
            let srcFreq = frequencyScore(token, language: .hebrew)
            let srcBuiltin = builtinValidator.confidence(for: token, language: .hebrew)

            let letterCount = token.filter { $0.isLetter }.count
            let isShort = letterCount <= 4

            // If the mapped candidate is whitelisted in the target language, allow correction even when the
            // source is a valid Hebrew word (this captures a lot of slang/abbreviations).
            // In automatic mode, avoid overriding very common/strong Hebrew words to reduce false positives.
            if best.isWhitelisted {
                let strongHebrew = (srcBuiltin >= 0.99) || (srcWord >= 0.95 && srcFreq >= 0.55)
                if mode == .automatic, strongHebrew {
                    // Fall through to the regular margin-based logic.
                } else {
                    let conf: Double = mode == .manual ? 0.95 : 0.85
                    return LanguageDecision(language: best.target, layoutHypothesis: best.hypothesis, confidence: conf, scores: [:])
                }
            }

            // For auto mode: require very strong target evidence + clear frequency advantage.
            // For manual mode: be a bit more permissive.
            let minTargetWord = mode == .manual ? 0.90 : 0.90
            let minTargetFreq = mode == .manual ? 0.25 : 0.25
            let minFreqGain = mode == .manual ? 0.08 : 0.10

            let sourceLooksIntentionallyHebrew = srcBuiltin >= 0.99 && srcWord >= 0.95
            let sourceHasFinalArtefact = endsWithHebrewNonFinalForm(token)

            if !sourceLooksIntentionallyHebrew,
               best.targetWord >= minTargetWord,
               best.targetFreq >= minTargetFreq,
               best.targetFreq >= srcFreq + minFreqGain,
               (isShort || sourceHasFinalArtefact || srcWord < 0.90) {
                let conf: Double = mode == .manual ? 0.90 : 0.82
                return LanguageDecision(language: best.target, layoutHypothesis: best.hypothesis, confidence: conf, scores: [:])
            }
        }

        // Only accept if the best mapped hypothesis is substantially better than any as-is option.
        let letterCount = token.filter { $0.isLetter }.count
        var requiredMargin = letterCount <= 3 ? thresholds.shortWordMargin : thresholds.longWordMargin
        if dominant == .hebrew {
            requiredMargin = letterCount <= 3 ? 0.10 : max(0.25, requiredMargin - 0.40)
        }
        if dominant == .hebrew, endsWithHebrewNonFinalForm(token) {
            // Reduce the barrier a bit: Hebrew words ending in non-final forms are often mapping artefacts.
            requiredMargin = max(0.10, requiredMargin - 0.10)
        }
        guard best.q >= bestAsIs + requiredMargin else { return nil }
        guard best.targetWord >= thresholds.wordConfidenceMin else { return nil }

        return LanguageDecision(language: best.target, layoutHypothesis: best.hypothesis, confidence: 0.95, scores: [:])
    }

    private func isTechnicalToken(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }

        // Unix-like paths
        if token.hasPrefix("/"), token.contains("/") {
            return true
        }

        // Windows paths: C:\... or C:/...
        if token.count >= 3 {
            let chars = Array(token)
            if chars[1] == ":", (chars[2] == "\\" || chars[2] == "/"), chars[0].isLetter {
                return true
            }
        }

        // UUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
        if isUUID(token) { return true }

        // Semver-like tokens: v1.2.3, 1.2.3, 1.2
        if isSemver(token) { return true }

        // Simple filename.ext (no path separators)
        if !token.contains("/") && !token.contains("\\"),
           let dot = token.lastIndex(of: "."),
           dot != token.startIndex,
           dot != token.index(before: token.endIndex) {
            let ext = token[token.index(after: dot)...]
            if ext.count <= 8, ext.allSatisfy({ $0.isLetter || $0.isNumber }) {
                let base = token[..<dot]
                if base.contains(where: { $0.isLetter }) {
                    return true
                }
            }
        }

        return false
    }

    private func isUUID(_ token: String) -> Bool {
        let chars = Array(token.lowercased())
        guard chars.count == 36 else { return false }
        let dashIdx: Set<Int> = [8, 13, 18, 23]
        for (i, ch) in chars.enumerated() {
            if dashIdx.contains(i) {
                if ch != "-" { return false }
                continue
            }
            let isHex = (ch >= "0" && ch <= "9") || (ch >= "a" && ch <= "f")
            if !isHex { return false }
        }
        return true
    }

    private func isSemver(_ token: String) -> Bool {
        var s = token
        if s.hasPrefix("v") || s.hasPrefix("V") {
            s.removeFirst()
        }
        let parts = s.split(separator: ".")
        guard parts.count >= 2, parts.count <= 4 else { return false }
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return false }
        return true
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
