import Foundation
import Carbon
import AppKit

/// Maps characters between different keyboard layouts using a data-driven approach.
public final class LayoutMapper: @unchecked Sendable {
    private var layoutData: LayoutData?
    
    // Cache: LayoutID -> [Character : (Key: String, Modifier: String)]
    private var charToKeyMap: [String: [Character: (key: String, mod: String)]] = [:]
    // Cache: LayoutID -> [Character : [(Key: String, Modifier: String)]]
    // Some layouts (e.g. phonetic Hebrew) intentionally repeat letters on multiple keys; this makes
    // conversion ambiguous and requires disambiguation when converting back to EN/RU.
    private var charToKeyCandidates: [String: [Character: [(key: String, mod: String)]]] = [:]
    
    // Detected user layouts: Language -> LayoutID
    private var activeLayouts: [Language: String] = [:]
    
    // All available layouts per language for brute-force conversion
    private var allLayoutsPerLanguage: [Language: [String]] = [:]
    private var layoutLanguageById: [String: Language] = [:]
    private var ambiguousLayoutIds: Set<String> = []

    private lazy var wordValidator: WordValidator = HybridWordValidator()
    private lazy var ngramModels: [Language: NgramLanguageModel] = {
        var out: [Language: NgramLanguageModel] = [:]
        if let ru = try? NgramLanguageModel.loadLanguage("ru") { out[.russian] = ru }
        if let en = try? NgramLanguageModel.loadLanguage("en") { out[.english] = en }
        if let he = try? NgramLanguageModel.loadLanguage("he") { out[.hebrew] = he }
        return out
    }()
    private lazy var unigramModels: [Language: WordFrequencyModel] = {
        var out: [Language: WordFrequencyModel] = [:]
        if let ru = try? WordFrequencyModel.loadLanguage("ru") { out[.russian] = ru }
        if let en = try? WordFrequencyModel.loadLanguage("en") { out[.english] = en }
        if let he = try? WordFrequencyModel.loadLanguage("he") { out[.hebrew] = he }
        return out
    }()
    
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
            layoutLanguageById[layout.id] = lang
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

        func modRank(_ mod: String) -> Int {
            // Prefer mappings that do not require modifiers. This improves reversibility
            // and reduces accidental case shifts when converting back-and-forth.
            switch mod {
            case "n": return 0
            case "s": return 1
            case "a": return 2
            case "sa": return 3
            default: return 99
            }
        }
        
        for (keyCode, layoutsMap) in map {
            for (layoutID, mapping) in layoutsMap {
                if charToKeyMap[layoutID] == nil { charToKeyMap[layoutID] = [:] }
                if charToKeyCandidates[layoutID] == nil { charToKeyCandidates[layoutID] = [:] }
                
                for (mod, charString) in [("n", mapping.n), ("s", mapping.s), ("a", mapping.a), ("sa", mapping.sa)] {
                    if let s = charString, let char = s.first, s.count == 1 {
                        charToKeyCandidates[layoutID]?[char, default: []].append((key: keyCode, mod: mod))
                        if let existing = charToKeyMap[layoutID]?[char] {
                            if modRank(mod) < modRank(existing.mod) {
                                charToKeyMap[layoutID]?[char] = (key: keyCode, mod: mod)
                            }
                        } else {
                            charToKeyMap[layoutID]?[char] = (key: keyCode, mod: mod)
                        }
                    }
                }
            }
        }

        // Identify layouts with ambiguous reverse-mapping (same character on multiple keys).
        for (layoutID, chars) in charToKeyCandidates {
            if chars.values.contains(where: { $0.count > 1 }) {
                ambiguousLayoutIds.insert(layoutID)
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

    /// Convert using Language enum with auto-detected layouts, but with disambiguation for
    /// layouts that repeat letters on multiple keys (e.g. Hebrew QWERTY phonetic).
    public func convertBest(_ text: String, from: Language, to: Language, activeLayouts: [String: String]? = nil) -> String? {
        let fromID = activeLayouts?[from.rawValue] ?? self.activeLayouts[from] ?? "us"
        let toID = activeLayouts?[to.rawValue] ?? self.activeLayouts[to] ?? "us"
        return convertBest(text, fromLayout: fromID, toLayout: toID)
    }

    public func convertBest(_ text: String, fromLayout: String, toLayout: String) -> String? {
        if fromLayout == toLayout { return text }
        guard let sourceMap = charToKeyMap[fromLayout],
              let fullMap = layoutData?.map else { return nil }

        guard ambiguousLayoutIds.contains(fromLayout),
              let candidatesMap = charToKeyCandidates[fromLayout],
              let targetLanguage = layoutLanguageById[toLayout],
              let targetNgram = ngramModels[targetLanguage] else {
            // No ambiguity or no LM available -> deterministic conversion.
            return convert(text, fromLayout: fromLayout, toLayout: toLayout)
        }
        let targetUnigram = unigramModels[targetLanguage]

        var result = ""
        result.reserveCapacity(text.count)

        var buffer = ""
        buffer.reserveCapacity(text.count)

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            if let converted = convertAmbiguousWord(buffer, fromLayout: fromLayout, toLayout: toLayout, candidatesMap: candidatesMap, fullMap: fullMap, targetLanguage: targetLanguage, targetNgram: targetNgram, targetUnigram: targetUnigram) {
                result.append(contentsOf: converted)
            } else {
                result.append(contentsOf: buffer)
            }
            buffer.removeAll(keepingCapacity: true)
        }

        var convertibleCache: [Character: Bool] = [:]
        convertibleCache.reserveCapacity(64)

        func isConvertibleWordChar(_ ch: Character) -> Bool {
            if ch.isLetter { return true }
            if let cached = convertibleCache[ch] { return cached }

            guard let keyCands = candidatesMap[ch], !keyCands.isEmpty else {
                convertibleCache[ch] = false
                return false
            }

            for (key, mod) in keyCands {
                guard let mapping = fullMap[key]?[toLayout] else { continue }
                let targetChar: String?
                switch mod {
                case "n": targetChar = mapping.n
                case "s": targetChar = mapping.s
                case "a": targetChar = mapping.a
                case "sa": targetChar = mapping.sa
                default: targetChar = nil
                }
                if let s = targetChar, s.count == 1, let c = s.first, c.isLetter {
                    convertibleCache[ch] = true
                    return true
                }
            }

            convertibleCache[ch] = false
            return false
        }

        for char in text {
            if isConvertibleWordChar(char) {
                buffer.append(char)
                continue
            }

            flushBuffer()

            // Convert non-letters deterministically (punctuation often isn't ambiguous).
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

        flushBuffer()
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
            if let converted = convertBest(text, fromLayout: srcLayout, toLayout: toID),
               converted != text {  // Only include if actually changed
                results.append((srcLayout, converted))
            }
        }
        return results
    }

    private func convertAmbiguousWord(
        _ word: String,
        fromLayout: String,
        toLayout: String,
        candidatesMap: [Character: [(key: String, mod: String)]]?,
        fullMap: [String: [String: KeyMapping]],
        targetLanguage: Language?,
        targetNgram: NgramLanguageModel?
        ,
        targetUnigram: WordFrequencyModel?
    ) -> String? {
        guard let candidatesMap else { return nil }
        guard let targetNgram else { return nil }
        guard !word.isEmpty else { return "" }

        func modPenalty(_ mod: String) -> Double {
            // Prefer mappings without modifiers; avoid alt/option outputs for "word" decoding.
            switch mod {
            case "n": return 0.0
            case "s": return 0.15
            case "a": return 0.65
            case "sa": return 0.80
            default: return 1.0
            }
        }

        // Build per-position candidate output characters with a penalty based on modifiers.
        var perPos: [[(c: Character, penalty: Double)]] = []
        perPos.reserveCapacity(word.count)

        for ch in word {
            let keyCands = candidatesMap[ch] ?? []
            var bestPenaltyByChar: [Character: Double] = [:]
            bestPenaltyByChar.reserveCapacity(max(1, keyCands.count))

            for (key, mod) in keyCands {
                guard let mapping = fullMap[key]?[toLayout] else { continue }
                let targetChar: String?
                switch mod {
                case "n": targetChar = mapping.n
                case "s": targetChar = mapping.s
                case "a": targetChar = mapping.a
                case "sa": targetChar = mapping.sa
                default: targetChar = nil
                }
                if let s = targetChar, s.count == 1, let c = s.first, c.isLetter {
                    let p = modPenalty(mod)
                    if let existing = bestPenaltyByChar[c] {
                        if p < existing { bestPenaltyByChar[c] = p }
                    } else {
                        bestPenaltyByChar[c] = p
                    }
                }
            }

            if bestPenaltyByChar.isEmpty {
                perPos.append([(c: ch, penalty: 0.0)])
            } else {
                // Deterministic order: lowest penalty first, then lexicographic.
                var opts = bestPenaltyByChar.map { (c: $0.key, penalty: $0.value) }
                opts.sort { (a, b) in
                    if a.penalty != b.penalty { return a.penalty < b.penalty }
                    return a.c < b.c
                }
                perPos.append(opts)
            }
        }

        let maxBrute = 500_000
        let product = perPos.reduce(1) { acc, opts in
            if acc > maxBrute { return acc }
            return acc * max(1, opts.count)
        }

        func fullScore(_ candidate: String) -> Double {
            let wconf: Double
            if let targetUnigram {
                wconf = targetUnigram.contains(candidate) ? 1.0 : 0.0
            } else {
                wconf = targetLanguage.map { wordValidator.confidence(for: candidate, language: $0) } ?? 0.0
            }
            let freq = targetUnigram?.score(candidate) ?? 0.0
            let ngram = targetNgram.normalizedScore(candidate)
            let ngramWeight = candidate.count >= 3 ? 0.8 : 0.0
            let freqWeight = candidate.count <= 3 ? 0.8 : 1.4
            let builtinBonus: Double
            if let targetLanguage, BuiltinLexicon.contains(candidate, language: targetLanguage) {
                builtinBonus = candidate.count <= 3 ? 1.2 : 0.6
            } else {
                builtinBonus = 0.0
            }
            return (2.6 * wconf) + (freqWeight * freq) + (ngramWeight * ngram) + builtinBonus
        }

        // When ambiguity is limited, brute-force all candidates and choose the best by scoring.
        // (Product is driven only by ambiguous Hebrew-QWERTY duplicates, not word length.)
        if product <= maxBrute {
            var best: (String, Double) = ("", -1e18)

            func rec(_ i: Int, _ buf: inout [Character], _ penaltySum: Double) {
                if i == perPos.count {
                    let candidate = String(buf)
                    let score = fullScore(candidate) - penaltySum
                    if score > best.1 {
                        best = (candidate, score)
                    }
                    return
                }
                for opt in perPos[i] {
                    buf.append(opt.c)
                    rec(i + 1, &buf, penaltySum + opt.penalty)
                    buf.removeLast()
                }
            }

            var buf: [Character] = []
            rec(0, &buf, 0.0)
            return best.0.isEmpty ? nil : best.0
        }

        // Beam search for longer words.
        struct Beam {
            var text: [Character]
            var score: Double
            var penalty: Double
        }

        let ambiguousPositions = perPos.filter { $0.count > 1 }.count
        let beamWidth = min(1024, max(64, 96 * max(1, ambiguousPositions)))
        var beams: [Beam] = [Beam(text: [], score: 0.0, penalty: 0.0)]

        func trigramIncrement(_ prefix: [Character], next: Character) -> Double {
            guard prefix.count >= 2 else { return 0.0 }
            let a = prefix[prefix.count - 2]
            let b = prefix[prefix.count - 1]
            return Double(targetNgram.lookup(a, b, next))
        }

        for opts in perPos {
            var nextBeams: [Beam] = []
            nextBeams.reserveCapacity(beams.count * opts.count)

            for beam in beams {
                for opt in opts {
                    var t = beam.text
                    t.append(opt.c)
                    let inc = trigramIncrement(beam.text, next: opt.c)
                    nextBeams.append(Beam(text: t, score: beam.score + inc, penalty: beam.penalty + opt.penalty))
                }
            }

            nextBeams.sort { $0.score > $1.score }
            if nextBeams.count > beamWidth {
                nextBeams = Array(nextBeams.prefix(beamWidth))
            }
            beams = nextBeams
            if beams.isEmpty { return nil }
        }

        // Evaluate final candidates with full (word + unigram + ngram) scoring.
        var bestFinal: (String, Double) = ("", -1e18)
        for beam in beams {
            let s = String(beam.text)
            let score = fullScore(s) - beam.penalty
            if score > bestFinal.1 {
                bestFinal = (s, score)
            }
        }
        return bestFinal.0.isEmpty ? beams.first.map { String($0.text) } : bestFinal.0
    }
}
