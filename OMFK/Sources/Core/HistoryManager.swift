import Foundation
import SwiftUI

/// Shared history storage accessible from UI
@MainActor
final class HistoryManager: ObservableObject {
    static let shared = HistoryManager()
    
    @Published var records: [HistoryRecord] = []
    
    struct HistoryRecord: Identifiable {
        let id = UUID()
        let original: String
        let corrected: String
        let fromLang: Language
        let toLang: Language
        let timestamp: Date
    }
    
    func add(original: String, corrected: String, from: Language, to: Language) {
        let record = HistoryRecord(
            original: original,
            corrected: corrected,
            fromLang: from,
            toLang: to,
            timestamp: Date()
        )
        records.insert(record, at: 0)
        if records.count > 50 {
            records.removeLast()
        }
    }
    
    func clear() {
        records.removeAll()
    }
}
