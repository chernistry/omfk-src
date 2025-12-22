import Foundation

/// Loads detection thresholds from JSON configuration
public struct ThresholdsConfig: Sendable {
    public static let shared = ThresholdsConfig()
    
    // Detection thresholds
    public let correctionThreshold: Double
    public let deepConfidenceMin: Double
    public let fallbackConfidence: Double
    
    // Validation thresholds
    public let targetWordMin: Double
    public let targetWordMargin: Double
    public let targetFreqMargin: Double
    public let targetNormMin: Double
    public let targetNormMargin: Double
    public let shortWordFreqMin: Double
    
    // Scoring thresholds
    public let shortWordMargin: Double
    public let longWordMargin: Double
    public let wordConfidenceMin: Double
    
    // Heuristic thresholds
    public let sourceWordConfMax: Double
    public let baseConfMin: Double
    
    private init() {
        guard let url = Bundle.module.url(forResource: "thresholds", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Defaults
            correctionThreshold = 0.45
            deepConfidenceMin = 0.7
            fallbackConfidence = 0.5
            targetWordMin = 0.80
            targetWordMargin = 0.20
            targetFreqMargin = 0.25
            targetNormMin = 0.75
            targetNormMargin = 0.15
            shortWordFreqMin = 0.60
            shortWordMargin = 0.25
            longWordMargin = 0.70
            wordConfidenceMin = 0.80
            sourceWordConfMax = 0.80
            baseConfMin = 0.75
            return
        }
        
        let detection = json["detection"] as? [String: Any] ?? [:]
        let validation = json["validation"] as? [String: Any] ?? [:]
        let scoring = json["scoring"] as? [String: Any] ?? [:]
        let heuristic = json["heuristic"] as? [String: Any] ?? [:]
        
        correctionThreshold = detection["correctionThreshold"] as? Double ?? 0.45
        deepConfidenceMin = detection["deepConfidenceMin"] as? Double ?? 0.7
        fallbackConfidence = detection["fallbackConfidence"] as? Double ?? 0.5
        
        targetWordMin = validation["targetWordMin"] as? Double ?? 0.80
        targetWordMargin = validation["targetWordMargin"] as? Double ?? 0.20
        targetFreqMargin = validation["targetFreqMargin"] as? Double ?? 0.25
        targetNormMin = validation["targetNormMin"] as? Double ?? 0.75
        targetNormMargin = validation["targetNormMargin"] as? Double ?? 0.15
        shortWordFreqMin = validation["shortWordFreqMin"] as? Double ?? 0.60
        
        shortWordMargin = scoring["shortWordMargin"] as? Double ?? 0.25
        longWordMargin = scoring["longWordMargin"] as? Double ?? 0.70
        wordConfidenceMin = scoring["wordConfidenceMin"] as? Double ?? 0.80
        
        sourceWordConfMax = heuristic["sourceWordConfMax"] as? Double ?? 0.80
        baseConfMin = heuristic["baseConfMin"] as? Double ?? 0.75
    }
}
