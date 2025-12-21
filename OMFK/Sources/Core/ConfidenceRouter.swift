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
    func route(token: String, context: DetectorContext) async -> LanguageDecision {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
             let duration = CFAbsoluteTimeGetCurrent() - startTime
             if duration > 0.05 {
                 logger.warning("⚠️ Slow detection: \(String(format: "%.1f", duration * 1000))ms for '\(token)'")
             }
        }
        
        // 1. FAST PATH: N-gram Only
        if token.count >= 4 {
            if let fastDecision = checkFastPath(token) {
                let threshold = await settings.fastPathThreshold
                if fastDecision.confidence >= threshold {
                    logger.info("🚀 Fast Path (N-gram) used: \(fastDecision.language.rawValue, privacy: .public) (conf: \(fastDecision.confidence))")
                    DecisionLogger.shared.logDecision(token: token, path: "FAST", result: fastDecision)
                    return fastDecision
                }
            }
        }
        
        // 2. STANDARD PATH: Ensemble
        // Context mapping: DetectorContext is conceptually similar to EnsembleContext
        let ensembleContext = EnsembleContext(lastLanguage: context.lastLanguage)
        let decision = await ensemble.classify(token, context: ensembleContext)
        
        let stdThreshold = await settings.standardPathThreshold
        if decision.confidence >= stdThreshold {
            logger.info("🛡️ Standard Path (Ensemble) used: \(decision.language.rawValue, privacy: .public) (conf: \(decision.confidence))")
            DecisionLogger.shared.logDecision(token: token, path: "STANDARD", result: decision)
            return decision
        }
        
        // 3. DEEP PATH: CoreML
        logger.info("🧠 Deep Path (CoreML) triggered for ambiguity: \(token)")
        
        if let (deepHypothesis, deepConf) = coreML.predict(token) {
            logger.info("🧠 Deep Path result: \(deepHypothesis.rawValue, privacy: .public) (conf: \(deepConf))")
            
            // Determine threshold based on whether it's a correction or just simple classification
            // "Corrective" hypotheses (e.g. ru_from_en) are more valuable to act on than just confirming "ru"
            let isCorrection = deepHypothesis.rawValue.contains("_from_")
            let threshold = isCorrection ? 0.6 : 0.8
            
            if deepConf > threshold {
                 let deepResult = LanguageDecision(
                    language: deepHypothesis.targetLanguage, 
                    layoutHypothesis: deepHypothesis,
                    confidence: deepConf,
                    scores: [:] 
                )
                DecisionLogger.shared.logDecision(token: token, path: "DEEP", result: deepResult)
                return deepResult
            } else {
                 // Log why we rejected it
                 let rejectedMsg = "REJECTED_DEEP: \(deepHypothesis.rawValue) (\(String(format: "%.2f", deepConf))) < \(threshold)"
                 DecisionLogger.shared.log(rejectedMsg)
            }
        }
        
        logger.info("⚠️ Falling back to Standard Path result after Deep Path (low confidence)")
        DecisionLogger.shared.logDecision(token: token, path: "FALLBACK", result: decision)
        return decision
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
