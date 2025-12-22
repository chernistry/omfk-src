import Foundation
import Carbon

/// Maps characters between different keyboard layouts using a data-driven approach.
public final class LayoutMapper: @unchecked Sendable {
    private var layoutData: LayoutData?
    
    // Cache: LayoutID -> [Character : (Key: String, Modifier: String)]
    private var charToKeyMap: [String: [Character: (key: String, mod: String)]] = [:]
    
    // Detected user layouts: Language -> LayoutID
    private var activeLayouts: [Language: String] = [:]
    
    // All available layouts per language for brute-force conversion
    private var allLayoutsPerLanguage: [Language: [String]] = [:]
    
    public static let shared = LayoutMapper()
    
    public init() {
        loadLayoutData()
        buildMaps()
        buildAllLayoutsPerLanguage()
        detectActiveLayouts()
    }
    
    private func buildAllLayoutsPerLanguage() {
        guard let layouts = layoutData?.layouts else { return }
        for layout in layouts {
            guard let lang = Language(rawValue: layout.language) else { continue }
            if allLayoutsPerLanguage[lang] == nil { allLayoutsPerLanguage[lang] = [] }
            allLayoutsPerLanguage[lang]!.append(layout.id)
        }
    }
    
    private func loadLayoutData() {
        guard let url = Bundle.module.url(forResource: "layouts", withExtension: "json") else {
            print("LayoutMapper: Could not find layouts.json in bundle.")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            self.layoutData = try JSONDecoder().decode(LayoutData.self, from: data)
        } catch {
            print("LayoutMapper: Failed to decode layouts.json: \(error)")
        }
    }
    
    private func buildMaps() {
        guard let map = layoutData?.map else { return }
        
        for (keyCode, layoutsMap) in map {
            for (layoutID, mapping) in layoutsMap {
                if charToKeyMap[layoutID] == nil { charToKeyMap[layoutID] = [:] }
                
                for (mod, charString) in [("n", mapping.n), ("s", mapping.s), ("a", mapping.a), ("sa", mapping.sa)] {
                    if let s = charString, let char = s.first, s.count == 1 {
                        if charToKeyMap[layoutID]?[char] == nil {
                            charToKeyMap[layoutID]?[char] = (key: keyCode, mod: mod)
                        }
                    }
                }
            }
        }
    }
    
    /// Detects user's active keyboard layouts from macOS
    private func detectActiveLayouts() {
        let conditions: CFDictionary = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable as String: true
        ] as CFDictionary
        
        guard let sources = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource] else {
            setDefaults()
            return
        }
        
        guard let layouts = layoutData?.layouts else {
            setDefaults()
            return
        }
        
        // Build appleId -> layoutInfo lookup
        var appleIdToLayout: [String: LayoutInfo] = [:]
        for layout in layouts {
            appleIdToLayout[layout.appleId] = layout
        }
        
        // Match installed layouts
        for source in sources {
            guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                  TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil else { continue }
            
            let appleId = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            
            if let layoutInfo = appleIdToLayout[appleId],
               let lang = Language(rawValue: layoutInfo.language) {
                // First match wins for each language
                if activeLayouts[lang] == nil {
                    activeLayouts[lang] = layoutInfo.id
                    print("LayoutMapper: Detected \(lang.rawValue) -> \(layoutInfo.id) (\(layoutInfo.name))")
                }
            }
        }
        
        // Fill in defaults for missing languages
        setDefaults()
    }
    
    private func setDefaults() {
        if activeLayouts[.english] == nil { activeLayouts[.english] = "us" }
        if activeLayouts[.russian] == nil { activeLayouts[.russian] = "russianwin" }
        if activeLayouts[.hebrew] == nil { activeLayouts[.hebrew] = "hebrew" }
    }
    
    /// Returns the detected layout ID for a language
    public func layoutId(for language: Language) -> String {
        return activeLayouts[language] ?? "us"
    }
    
    /// Converts text from source layout to target layout
    public func convert(_ text: String, fromLayout: String, toLayout: String) -> String? {
        if fromLayout == toLayout { return text }
        
        guard let sourceMap = charToKeyMap[fromLayout],
              let fullMap = layoutData?.map else { return nil }
        
        var result = ""
        result.reserveCapacity(text.count)
        
        for char in text {
            if let (keyCode, mod) = sourceMap[char],
               let targetMapping = fullMap[keyCode]?[toLayout] {
                let targetChar: String?
                switch mod {
                case "n": targetChar = targetMapping.n
                case "s": targetChar = targetMapping.s
                case "a": targetChar = targetMapping.a
                case "sa": targetChar = targetMapping.sa
                default: targetChar = nil
                }
                result.append(targetChar ?? String(char))
            } else {
                result.append(char)
            }
        }
        return result
    }
    
    /// Convenience: Convert using Language enum with auto-detected layouts
    public func convert(_ text: String, from: Language, to: Language, activeLayouts: [String: String]? = nil) -> String? {
        let fromID = activeLayouts?[from.rawValue] ?? self.activeLayouts[from] ?? "us"
        let toID = activeLayouts?[to.rawValue] ?? self.activeLayouts[to] ?? "us"
        return convert(text, fromLayout: fromID, toLayout: toID)
    }
    
    /// Try ALL source layouts for a language and return all possible conversions
    /// This handles cases where user might have different layout variant than detected
    public func convertAllVariants(_ text: String, from: Language, to: Language, activeLayouts: [String: String]? = nil) -> [(layout: String, result: String)] {
        guard let sourceLayouts = allLayoutsPerLanguage[from] else { return [] }
        let toID = activeLayouts?[to.rawValue] ?? self.activeLayouts[to] ?? "us"
        
        var results: [(String, String)] = []
        for srcLayout in sourceLayouts {
            if let converted = convert(text, fromLayout: srcLayout, toLayout: toID),
               converted != text {  // Only include if actually changed
                results.append((srcLayout, converted))
            }
        }
        return results
    }
}
