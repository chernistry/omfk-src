import Foundation
import os.log

/// Layout-aware n-gram detector actor
/// Detects the most probable language and layout hypothesis for a given token
actor LayoutNgramDetector {
    private let ruModel: NgramLanguageModel
    private let enModel: NgramLanguageModel
    private let heModel: NgramLanguageModel
    private let logger = Logger.detection
    
    init() {
        // Try to load real models from resources
        // Fallback to mock data if resources are missing (e.g. during certain test configurations)
        
        if let ru = try? NgramLanguageModel.loadLanguage("ru") {
            self.ruModel = ru
        } else {
            logger.warning("Failed to load Russian model, using mock data")
            self.ruModel = NgramLanguageModel(logProbs: MockNgramData.russianTrigrams)
        }
        
        if let en = try? NgramLanguageModel.loadLanguage("en") {
            self.enModel = en
        } else {
            logger.warning("Failed to load English model, using mock data")
            self.enModel = NgramLanguageModel(logProbs: MockNgramData.englishTrigrams)
        }
        
        if let he = try? NgramLanguageModel.loadLanguage("he") {
            self.heModel = he
        } else {
            logger.warning("Failed to load Hebrew model, using mock data")
            self.heModel = NgramLanguageModel(logProbs: MockNgramData.hebrewTrigrams)
        }
    }
    
    /// Score a token against all layout hypotheses
    /// Returns scores for each hypothesis, the best one, and confidence
    nonisolated func score(token: String, context: LayoutContext? = nil) -> LayoutScores {
        guard token.count >= 2 else {
            // Too short to score reliably
            return LayoutScores(
                scores: [:],
                best: .en,
                confidence: 0.0
            )
        }
        
        var scores: [LanguageHypothesis: Float] = [:]
        
        // Hypothesis 1: as-is Russian
        scores[.ru] = ruModel.score(token)
        
        // Hypothesis 2: as-is English
        scores[.en] = enModel.score(token)
        
        // Hypothesis 3: as-is Hebrew
        scores[.he] = heModel.score(token)
        
        // Hypothesis 4: English typed on Russian layout (e.g., "ghbdtn" → "привет")
        if let ruMapped = LayoutMapper.convert(token, from: .english, to: .russian) {
            scores[.enFromRuLayout] = ruModel.score(ruMapped)
        } else {
            scores[.enFromRuLayout] = -100.0
        }
        
        // Hypothesis 5: English typed on Hebrew layout
        if let heMapped = LayoutMapper.convert(token, from: .english, to: .hebrew) {
            scores[.enFromHeLayout] = heModel.score(heMapped)
        } else {
            scores[.enFromHeLayout] = -100.0
        }
        
        // Find best hypothesis
        let best = scores.max(by: { $0.value < $1.value })?.key ?? .en
        
        // Calculate confidence using margin between top-1 and top-2
        let sortedScores = scores.values.sorted(by: >)
        let confidence: Double
        if sortedScores.count >= 2 {
            let margin = Double(sortedScores[0] - sortedScores[1])
            // Normalize margin to [0, 1] using sigmoid-like function
            // Larger margins = higher confidence
            confidence = min(1.0, max(0.0, (margin / 2.0 + 0.5)))
        } else {
            confidence = 0.5
        }
        
        return LayoutScores(
            scores: scores,
            best: best,
            confidence: confidence
        )
    }
}
