import Foundation
import AppKit

actor CorrectionEngine {
    private let detector = LanguageDetector()
    private let settings: SettingsManager
    private var history: [CorrectionRecord] = []
    
    struct CorrectionRecord: Identifiable {
        let id = UUID()
        let original: String
        let corrected: String
        let fromLang: Language
        let toLang: Language
        let timestamp: Date
    }
    
    init(settings: SettingsManager) {
        self.settings = settings
    }
    
    func shouldCorrect(for bundleId: String?) async -> Bool {
        guard await settings.isEnabled else { return false }
        if let id = bundleId, await settings.isExcluded(bundleId: id) {
            return false
        }
        return true
    }
    
    func correctText(_ text: String, expectedLayout: Language?) async -> String? {
        guard !text.isEmpty else { return nil }
        
        let detectedLang = await detector.detect(text)
        guard let detected = detectedLang else { return nil }
        
        // If expected layout is set and doesn't match detected, correct it
        if let expected = expectedLayout, expected != detected {
            let corrected = LayoutMapper.convert(text, from: detected, to: expected)
            if let result = corrected {
                addToHistory(original: text, corrected: result, from: detected, to: expected)
            }
            return corrected
        }
        
        // Auto-detect wrong layout: if text looks like gibberish, try converting
        let targetLang = await settings.preferredLanguage
        if detected != targetLang {
            let corrected = LayoutMapper.convert(text, from: detected, to: targetLang)
            if let result = corrected {
                addToHistory(original: text, corrected: result, from: detected, to: targetLang)
            }
            return corrected
        }
        
        return nil
    }
    
    func getHistory() async -> [CorrectionRecord] {
        return history
    }
    
    func clearHistory() async {
        history.removeAll()
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
