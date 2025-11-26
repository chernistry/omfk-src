import Foundation

/// Hypothesis about the language and layout configuration
enum LanguageHypothesis: String, CaseIterable, Sendable {
    case ru               // Russian as-is
    case en               // English as-is
    case he               // Hebrew as-is
    case enFromRuLayout   // English typed on Russian layout
    case enFromHeLayout   // English typed on Hebrew layout
    
    var targetLanguage: Language {
        switch self {
        case .ru: return .russian
        case .en, .enFromRuLayout, .enFromHeLayout: return .english
        case .he: return .hebrew
        }
    }
}

/// Scores for different layout hypotheses with confidence
struct LayoutScores: Sendable {
    let scores: [LanguageHypothesis: Float]
    let best: LanguageHypothesis
    let confidence: Double  // In range [0, 1]
}

/// Context for layout detection (minimal in this ticket, for future use)
struct LayoutContext: Sendable {
    let lastLanguage: LanguageHypothesis?
    
    init(lastLanguage: LanguageHypothesis? = nil) {
        self.lastLanguage = lastLanguage
    }
}

/// N-gram language model using trigram log-probabilities
struct NgramLanguageModel: Sendable {
    private let logProbs: [UInt32: Float]
    private let smoothingValue: Float
    
    init(logProbs: [UInt32: Float], smoothingValue: Float = -10.0) {
        self.logProbs = logProbs
        self.smoothingValue = smoothingValue
    }
    
    /// Compute trigram hash from 3 characters
    static func trigramHash(_ c1: Character, _ c2: Character, _ c3: Character) -> UInt32 {
        guard let s1 = c1.unicodeScalars.first,
              let s2 = c2.unicodeScalars.first,
              let s3 = c3.unicodeScalars.first else {
            return 0
        }
        // Pack three Unicode scalar values into UInt32
        // Use lower 10 bits for each character (supports up to U+03FF)
        let hash = (UInt32(s1.value & 0x3FF) << 20) |
                   (UInt32(s2.value & 0x3FF) << 10) |
                   UInt32(s3.value & 0x3FF)
        return hash
    }
    
    /// Score a text by summing log-probabilities of its trigrams
    func score(_ text: String) -> Float {
        let normalized = text.lowercased().filter { $0.isLetter }
        guard normalized.count >= 3 else {
            return smoothingValue * Float(max(1, normalized.count))
        }
        
        var totalScore: Float = 0.0
        var trigramCount = 0
        
        let chars = Array(normalized)
        for i in 0...(chars.count - 3) {
            let hash = Self.trigramHash(chars[i], chars[i+1], chars[i+2])
            let prob = logProbs[hash] ?? smoothingValue
            totalScore += prob
            trigramCount += 1
        }
        
        // Normalize by number of trigrams to make scores comparable
        return trigramCount > 0 ? totalScore / Float(trigramCount) : smoothingValue
    }
    
    /// Lookup log-probability for a specific trigram
    func lookup(_ c1: Character, _ c2: Character, _ c3: Character) -> Float {
        let hash = Self.trigramHash(c1, c2, c3)
        return logProbs[hash] ?? smoothingValue
    }
}
