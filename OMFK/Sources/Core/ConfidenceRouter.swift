import Foundation
import os.log

/// Orchestrates language detection by routing requests through Fast (N-gram) and Standard (Ensemble) paths
/// based on confidence thresholds.
actor ConfidenceRouter {
    private let ensemble = LanguageEnsemble()
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
    
    private let logger = Logger.detection
    private let settings: SettingsManager
    
    init(settings: SettingsManager) {
        self.settings = settings
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
                 logger.warning("⚠️ Slow detection: \(String(format: "%.1f", duration * 1000))ms for '\(token)'")
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
            let ensembleContext = EnsembleContext(lastLanguage: context.lastLanguage)
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
        
        // -- STEP 2: ALWAYS invoke CoreML to check for layout mismatch --
        // CoreML can detect "_from_" hypotheses that contradict the baseline.
        logger.info("🧠 Deep Path (CoreML) checking for layout mismatch: \(token)")
        
        if let (deepHypothesis, deepConf) = coreML.predict(token) {
            logger.info("🧠 Deep Path result: \(deepHypothesis.rawValue, privacy: .public) (conf: \(deepConf))")
            
            let isCorrection = deepHypothesis.rawValue.contains("_from_")
            
            if isCorrection {
                // CoreML thinks this is a layout mismatch (e.g. "en_from_ru").
                // VALIDATION: Before accepting, convert the text and verify the result
                // is actually valid in the target language using N-gram scoring.
                let correctionThreshold = 0.70 // Raised threshold
                
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
                    
                    // Try to convert and validate
                    if let converted = LayoutMapper.shared.convert(token, from: sourceLayout, to: targetLanguage) {
                        // Score the converted text using N-gram
                        let targetScore = scoreWithNgram(converted, language: targetLanguage)
                        let sourceScore = scoreWithNgram(token, language: baseline.language)
                        
                        logger.info("🔍 Validation: '\(token)' → '\(converted)' | source_score=\(String(format: "%.2f", sourceScore)) target_score=\(String(format: "%.2f", targetScore))")
                        
                        // Only accept correction if:
                        // 1. Target score is good (converted text is valid)
                        // 2. Target score is significantly better than source score (original was gibberish)
                        let isValidConversion = targetScore > -6.0 && (targetScore - sourceScore) > 1.0
                        
                        if isValidConversion {
                            let deepResult = LanguageDecision(
                                language: targetLanguage, 
                                layoutHypothesis: deepHypothesis,
                                confidence: deepConf,
                                scores: [:] 
                            )
                            DecisionLogger.shared.logDecision(token: token, path: "DEEP_CORRECTION", result: deepResult)
                            return deepResult
                        } else {
                            let rejectedMsg = "REJECTED_VALIDATION: \(deepHypothesis.rawValue) | converted='\(converted)' srcScore=\(String(format: "%.2f", sourceScore)) tgtScore=\(String(format: "%.2f", targetScore))"
                            DecisionLogger.shared.log(rejectedMsg)
                        }
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
        DecisionLogger.shared.logDecision(token: token, path: baselinePath, result: baseline)
        return baseline
    }
    
    private func checkFastPath(_ text: String) -> LanguageDecision? {
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
        let confidence = min(1.0, 0.5 + Double(margin) * 0.2)
        
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
