import Foundation

/// Loads language whitelists from JSON configuration
public struct WhitelistConfig: Sendable {
    public static let shared = WhitelistConfig()
    
    public let english: Set<String>
    public let russian: Set<String>
    public let hebrew: Set<String>
    
    private init() {
        guard let url = Bundle.module.url(forResource: "whitelists", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            english = []
            russian = []
            hebrew = []
            return
        }
        
        func loadWords(_ key: String) -> Set<String> {
            guard let langData = json[key] as? [String: Any],
                  let words = langData["words"] as? [String] else {
                return []
            }
            return Set(words.map { $0.lowercased() })
        }
        
        english = loadWords("english")
        russian = loadWords("russian")
        hebrew = loadWords("hebrew")
    }
    
    /// Check if all words in text are whitelisted for given language
    public func isWhitelisted(_ text: String, language: Language) -> Bool {
        let words = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
        
        guard !words.isEmpty else { return false }
        
        let whitelist: Set<String>
        switch language {
        case .english: whitelist = english
        case .russian: whitelist = russian
        case .hebrew: whitelist = hebrew
        }
        
        return words.allSatisfy { whitelist.contains($0) }
    }
    
    /// Check if text matches any language whitelist, returns the language if found
    public func whitelistedLanguage(_ text: String) -> Language? {
        if isWhitelisted(text, language: .english) { return .english }
        if isWhitelisted(text, language: .russian) { return .russian }
        if isWhitelisted(text, language: .hebrew) { return .hebrew }
        return nil
    }
}
