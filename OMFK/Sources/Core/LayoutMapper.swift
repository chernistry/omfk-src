import Foundation

/// Maps characters between different keyboard layouts using a data-driven approach.
public final class LayoutMapper: @unchecked Sendable {
    private var layoutData: LayoutData?
    
    // Cache: LayoutID -> [Character : (Key: String, Modifier: String)]
    // We need to know which Key+Modifier produced a Character in a specifically named layout.
    private var charToKeyMap: [String: [Character: (key: String, mod: String)]] = [:]
    
    // Defines which layout ID is "default" for a given language if not specified in Settings.
    private let defaultLayouts: [Language: String] = [
        .english: "en_us",
        .russian: "ru_pc",
        .hebrew: "he_standard"
    ]
    
    /// Shared singleton instance for convenient access
    public static let shared = LayoutMapper()
    
    // Make init public for testing if needed, though usually shared is enough
    public init() {
        loadLayoutData()
        buildMaps()
    }
    
    private func loadLayoutData() {
        // ... (Keep existing loading logic, simplified for brevity in replacement if unchanged, 
        // but since I am replacing the whole class, I will include it)
        guard let url = Bundle.module.url(forResource: "layouts", withExtension: "json") else {
            print("LayoutMapper: Could not find layouts.json in bundle.")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            self.layoutData = try decoder.decode(LayoutData.self, from: data)
        } catch {
            print("LayoutMapper: Failed to decode layouts.json: \(error)")
        }
    }
    
    private func buildMaps() {
        guard let map = layoutData?.map else { return }
        let modifiers = ["n", "s", "a", "sa"]
        
        // Iterate over all keys: KeyCode -> [LayoutID -> Mapping]
        for (keyCode, layoutsMap) in map {
            for (layoutID, mapping) in layoutsMap {
                
                // For this LayoutID, map Char -> (KeyCode, Mod)
                if charToKeyMap[layoutID] == nil {
                    charToKeyMap[layoutID] = [:]
                }
                
                // Check each modifier
                for mod in modifiers {
                    let charString: String?
                    switch mod {
                    case "n": charString = mapping.n
                    case "s": charString = mapping.s
                    case "a": charString = mapping.a
                    case "sa": charString = mapping.sa
                    default: charString = nil
                    }
                    
                    if let s = charString, let char = s.first, s.count == 1 {
                        // Store mapping. Prioritize simple modifiers (n) found earlier.
                        if charToKeyMap[layoutID]?[char] == nil {
                            charToKeyMap[layoutID]?[char] = (key: keyCode, mod: mod)
                        }
                    }
                }
            }
        }
        
        // Handle aliases? keys in charToKeyMap are LayoutIDs.
        // We should ensure aliases point to real IDs before lookup.
    }
    
    /// Converts text from a specific source layout to a target layout.
    /// - Parameters:
    ///   - text: The input string.
    ///   - fromLayout: The ID of the layout the text was typed in (e.g., "en_us").
    ///   - toLayout: The ID of the target layout (e.g., "ru_pc").
    /// - Returns: The converted string, or nil if conversion isn't fully possible.
    public func convert(_ text: String, fromLayout: String, toLayout: String) -> String? {
        let fromID = resolveAlias(fromLayout)
        let toID = resolveAlias(toLayout)
        
        if fromID == toID { return text }
        
        // Ensure we have maps
        guard let sourceMap = charToKeyMap[fromID] else { return nil }
        // For target, we look up in layoutData directly using KeyCode
        guard let fullMap = layoutData?.map else { return nil }
        
        var result = ""
        result.reserveCapacity(text.count)
        
        for char in text {
            // 1. Find KeyCode used to type this char in Source Layout
            if let (keyCode, mod) = sourceMap[char] {
                // 2. Find what this KeyCode + Mod produces in Target Layout
                if let targetMapping = fullMap[keyCode]?[toID] {
                    let targetCharString: String?
                    switch mod {
                    case "n": targetCharString = targetMapping.n
                    case "s": targetCharString = targetMapping.s
                    case "a": targetCharString = targetMapping.a
                    case "sa": targetCharString = targetMapping.sa
                    default: targetCharString = nil
                    }
                    
                    if let t = targetCharString {
                        result.append(t)
                    } else {
                         // Key exists but produces nothing in this state? Keep original?
                        result.append(char)
                    }
                } else {
                    // Key doesn't exist in target layout? Keep original
                    result.append(char)
                }
            } else {
                // Character unique to source layout or not mapped? Keep original
                result.append(char)
            }
        }
        return result
    }
    
    /// Convenience: Convert using abstract Language enum.
    /// Uses default or configured layouts for these languages.
    /// - Parameters:
    ///   - activeLayouts: Optional dictionary mapping Language to layout ID. 
    ///                    If nil, uses internal defaults.
    public func convert(_ text: String, from: Language, to: Language, activeLayouts: [String: String]? = nil) -> String? {
        let fromKey = from.rawValue
        let toKey = to.rawValue
        
        let fromLayoutID = activeLayouts?[fromKey] ?? defaultLayouts[from] ?? defaultLayoutID(for: from)
        let toLayoutID = activeLayouts?[toKey] ?? defaultLayouts[to] ?? defaultLayoutID(for: to)
        
        return convert(text, fromLayout: fromLayoutID, toLayout: toLayoutID)
    }
    
    private func resolveAlias(_ layoutID: String) -> String {
        return layoutData?.layoutAliases[layoutID] ?? layoutID
    }
    
    private func defaultLayoutID(for language: Language) -> String {
        switch language {
        case .english: return "en_us"
        case .russian: return "ru_pc"
        case .hebrew: return "he_standard"
        }
    }
}
