import XCTest
@testable import OMFK

final class SyntheticEvaluationTests: XCTestCase {
    private struct Case {
        let intendedLanguage: Language
        let typedLanguage: Language
        let intendedText: String
        let typedText: String
        let expectedHypothesis: LanguageHypothesis
    }

    func testSyntheticEvaluationIfEnabled() async throws {
        guard ProcessInfo.processInfo.environment["OMFK_RUN_SYNTH_EVAL"] == "1" else {
            throw XCTSkip("Set OMFK_RUN_SYNTH_EVAL=1 to run synthetic evaluation (can be slow).")
        }

        let casesPerLanguage = Int(ProcessInfo.processInfo.environment["OMFK_SYNTH_EVAL_CASES_PER_LANG"] ?? "300") ?? 300
        let seed = UInt64(ProcessInfo.processInfo.environment["OMFK_SYNTH_EVAL_SEED"] ?? "42") ?? 42

        let activeLayouts = ["en": "us", "ru": "russianwin", "he": "hebrew_qwerty"]

        let settings = await MainActor.run { SettingsManager.shared }
        await MainActor.run {
            settings.isEnabled = true
            settings.activeLayouts = activeLayouts
        }

        let router = ConfidenceRouter(settings: settings)
        let threshold = await settings.standardPathThreshold

        let cases = generateCases(casesPerLanguage: casesPerLanguage, seed: seed, activeLayouts: activeLayouts)

        var correctOutput = 0
        var correctHypothesis = 0
        var totalsByCombo: [String: (ok: Int, total: Int)] = [:]
        var confusion: [LanguageHypothesis: [LanguageHypothesis: Int]] = [:]
        let diag = ProcessInfo.processInfo.environment["OMFK_SYNTH_EVAL_DIAG"] == "1"
        var mappingRecover: [String: (ok: Int, total: Int)] = [:]
        var mappingFailures: [String: [(typed: String, intended: String, recovered: String?)]] = [:]
        var outputFailures: [String: [(typed: String, intended: String, predicted: String, hyp: String, conf: Double)]] = [:]

        func key(_ intended: Language, _ typed: Language) -> String {
            "\(typed.rawValue)->\(intended.rawValue)"
        }

        for c in cases {
            let decision = await router.route(token: c.typedText, context: DetectorContext(lastLanguage: nil))
            let predictedHypothesis = decision.layoutHypothesis

            confusion[c.expectedHypothesis, default: [:]][predictedHypothesis, default: 0] += 1

            if predictedHypothesis == c.expectedHypothesis { correctHypothesis += 1 }

            let predictedOutput = applyDecision(
                typed: c.typedText,
                decision: decision,
                threshold: threshold,
                activeLayouts: activeLayouts
            )

            let okOut = predictedOutput == c.intendedText
            if okOut { correctOutput += 1 }

            let combo = key(c.intendedLanguage, c.typedLanguage)
            let curr = totalsByCombo[combo] ?? (0, 0)
            totalsByCombo[combo] = (curr.ok + (okOut ? 1 : 0), curr.total + 1)
            if diag, !okOut {
                var arr = outputFailures[combo] ?? []
                if arr.count < 12 {
                    arr.append((typed: c.typedText, intended: c.intendedText, predicted: predictedOutput, hyp: predictedHypothesis.rawValue, conf: decision.confidence))
                    outputFailures[combo] = arr
                }
            }

            if diag, c.typedLanguage != c.intendedLanguage {
                if let recovered = LayoutMapper.shared.convertBest(c.typedText, from: c.typedLanguage, to: c.intendedLanguage, activeLayouts: activeLayouts) {
                    let ok = recovered == c.intendedText
                    let r = mappingRecover[combo] ?? (0, 0)
                    mappingRecover[combo] = (r.ok + (ok ? 1 : 0), r.total + 1)
                    if !ok {
                        var arr = mappingFailures[combo] ?? []
                        if arr.count < 12 {
                            arr.append((typed: c.typedText, intended: c.intendedText, recovered: recovered))
                            mappingFailures[combo] = arr
                        }
                    }
                } else {
                    let r = mappingRecover[combo] ?? (0, 0)
                    mappingRecover[combo] = (r.ok, r.total + 1)
                    var arr = mappingFailures[combo] ?? []
                    if arr.count < 12 {
                        arr.append((typed: c.typedText, intended: c.intendedText, recovered: nil))
                        mappingFailures[combo] = arr
                    }
                }
            }
        }

        let outAcc = Double(correctOutput) / Double(cases.count)
        let hypAcc = Double(correctHypothesis) / Double(cases.count)

        print("\n=== SYNTHETIC EVAL ===")
        print("Cases: \(cases.count) (per-lang intended: \(casesPerLanguage))")
        print("Active layouts: \(activeLayouts)")
        print(String(format: "Output accuracy: %.2f%%", outAcc * 100))
        print(String(format: "Hypothesis accuracy: %.2f%%", hypAcc * 100))

        for combo in totalsByCombo.keys.sorted() {
            if let v = totalsByCombo[combo], v.total > 0 {
                let acc = Double(v.ok) / Double(v.total) * 100
                print(String(format: "  %@: %4d/%4d (%.1f%%)", combo, v.ok, v.total, acc))
            }
        }

        if diag {
            print("\nMapping recovery (typed->intended via LayoutMapper.convert):")
            for combo in mappingRecover.keys.sorted() {
                if let v = mappingRecover[combo], v.total > 0 {
                    let acc = Double(v.ok) / Double(v.total) * 100
                    print(String(format: "  %@: %4d/%4d (%.1f%%)", combo, v.ok, v.total, acc))
                }
            }

            if !mappingFailures.isEmpty {
                print("\nMapping failure samples (first 12 per combo):")
                for combo in mappingFailures.keys.sorted() {
                    guard let samples = mappingFailures[combo], !samples.isEmpty else { continue }
                    print("  \(combo):")
                    for s in samples {
                        let rec = s.recovered ?? "<nil>"
                        print("    typed=\(s.typed) | recovered=\(rec) | intended=\(s.intended)")
                    }
                }
            }

            if !outputFailures.isEmpty {
                print("\nOutput failure samples (first 12 per combo):")
                for combo in outputFailures.keys.sorted() {
                    guard let samples = outputFailures[combo], !samples.isEmpty else { continue }
                    print("  \(combo):")
                    for s in samples {
                        print("    typed=\(s.typed) | predicted=\(s.predicted) | intended=\(s.intended) | hyp=\(s.hyp) conf=\(String(format: "%.2f", s.conf))")
                    }
                }
            }
        }

        if let minAccStr = ProcessInfo.processInfo.environment["OMFK_SYNTH_EVAL_MIN_OUTPUT_ACC"],
           let minAcc = Double(minAccStr) {
            XCTAssertGreaterThanOrEqual(outAcc * 100, minAcc)
        }
    }

    // MARK: - Generation

    private func generateCases(
        casesPerLanguage: Int,
        seed: UInt64,
        activeLayouts: [String: String]
    ) -> [Case] {
        var rng = SplitMix64(seed: seed)

        let en = UnigramLexicon.load(lang: "en", minLen: 2, maxLen: 12, take: 200_000)
        let ru = UnigramLexicon.load(lang: "ru", minLen: 2, maxLen: 14, take: 200_000)
        let he = UnigramLexicon.load(lang: "he", minLen: 2, maxLen: 12, take: 200_000)

        let intendedSamples: [(Language, [String])] = [
            (.english, generateIntendedSamples(words: en, count: casesPerLanguage, rng: &rng)),
            (.russian, generateIntendedSamples(words: ru, count: casesPerLanguage, rng: &rng)),
            (.hebrew, generateIntendedSamples(words: he, count: casesPerLanguage, rng: &rng))
        ]

        var cases: [Case] = []
        cases.reserveCapacity(casesPerLanguage * 9)

        for (intendedLang, samples) in intendedSamples {
            for intendedText in samples {
                for typedLang in [Language.english, .russian, .hebrew] {
                    let typedText: String
                    if typedLang == intendedLang {
                        typedText = intendedText
                    } else {
                        typedText = LayoutMapper.shared.convert(intendedText, from: intendedLang, to: typedLang, activeLayouts: activeLayouts) ?? intendedText
                    }

                    let expected = expectedHypothesis(intended: intendedLang, typed: typedLang)

                    // Skip degenerate cases where mapping doesn't change anything.
                    if typedLang != intendedLang, typedText == intendedText { continue }

                    cases.append(Case(
                        intendedLanguage: intendedLang,
                        typedLanguage: typedLang,
                        intendedText: intendedText,
                        typedText: typedText,
                        expectedHypothesis: expected
                    ))
                }
            }
        }

        return cases
    }

    private func generateIntendedSamples(words: [String], count: Int, rng: inout SplitMix64) -> [String] {
        let filtered = words.filter { !$0.isEmpty }

        var out: [String] = []
        out.reserveCapacity(count)

        for _ in 0..<count {
            let roll = Int(rng.next() % 100)

            // Mix coverage:
            // - short words (2-3)
            // - medium words (4-8)
            // - phrases with spaces
            // - phrases with punctuation inside/around words

            func pick(from slice: ArraySlice<String>) -> String {
                let idx = Int(rng.next() % UInt64(slice.count))
                return slice[slice.startIndex + idx]
            }

            // Rank-stratified slices to avoid only "top-10" words.
            let top = filtered.prefix(min(filtered.count, 4000))
            let midStart = min(filtered.count, 20_000)
            let midEnd = min(filtered.count, 40_000)
            let tailStart = min(filtered.count, 150_000)
            let mid = midStart < midEnd ? filtered[midStart..<midEnd] : filtered[...]
            let tail = tailStart < filtered.count ? filtered[tailStart..<filtered.count] : filtered[...]

            func pickRankedWord(minLen: Int, maxLen: Int) -> String {
                // Pick which band first, then pick words until length fits (cap attempts).
                let bandRoll = Int(rng.next() % 100)
                let band: ArraySlice<String>
                if bandRoll < 50 { band = top }
                else if bandRoll < 85 { band = mid }
                else { band = tail }

                for _ in 0..<40 {
                    let w = pick(from: band)
                    let len = w.filter { $0.isLetter }.count
                    if len >= minLen && len <= maxLen { return w }
                }
                return pick(from: top)
            }

            if roll < 25 {
                out.append(pickRankedWord(minLen: 2, maxLen: 3))
            } else if roll < 55 {
                out.append(pickRankedWord(minLen: 4, maxLen: 8))
            } else if roll < 80 {
                // Phrase (2-6 words)
                let n = 2 + Int(rng.next() % 5)
                var parts: [String] = []
                parts.reserveCapacity(n)
                for j in 0..<n {
                    let w = pickRankedWord(minLen: j == 0 ? 2 : 2, maxLen: 10)
                    parts.append(w)
                }
                out.append(parts.joined(separator: " "))
            } else {
                // Punctuation-heavy phrase.
                // Examples:
                //   "word,word" / "word, word" / "word / word" / "word'word" / "(word) word"
                let w1 = pickRankedWord(minLen: 2, maxLen: 8)
                let w2 = pickRankedWord(minLen: 2, maxLen: 10)
                let w3 = pickRankedWord(minLen: 2, maxLen: 10)
                let punctRoll = Int(rng.next() % 6)
                switch punctRoll {
                case 0: out.append("\(w1), \(w2)")
                case 1: out.append("\(w1),\(w2)")
                case 2: out.append("\(w1) / \(w2)")
                case 3: out.append("(\(w1)) \(w2)")
                case 4: out.append("\(w1) \(w2)! \(w3)")
                default: out.append("\(w1) \(w2)")
                }
            }
        }

        return out
    }

    private func expectedHypothesis(intended: Language, typed: Language) -> LanguageHypothesis {
        if intended == typed { return intended.asHypothesis }
        switch (intended, typed) {
        case (.russian, .english): return .ruFromEnLayout
        case (.hebrew, .english): return .heFromEnLayout
        case (.english, .russian): return .enFromRuLayout
        case (.english, .hebrew): return .enFromHeLayout
        case (.hebrew, .russian): return .heFromRuLayout
        case (.russian, .hebrew): return .ruFromHeLayout
        default: return intended.asHypothesis
        }
    }

    private func applyDecision(
        typed: String,
        decision: LanguageDecision,
        threshold: Double,
        activeLayouts: [String: String]
    ) -> String {
        guard decision.layoutHypothesis.rawValue.contains("_from_"),
              decision.confidence >= threshold else {
            return typed
        }

        let sourceLayout: Language
        switch decision.layoutHypothesis {
        case .ruFromEnLayout, .heFromEnLayout:
            sourceLayout = .english
        case .enFromRuLayout, .heFromRuLayout:
            sourceLayout = .russian
        case .enFromHeLayout, .ruFromHeLayout:
            sourceLayout = .hebrew
        default:
            sourceLayout = .english
        }

        return LayoutMapper.shared.convertBest(typed, from: sourceLayout, to: decision.language, activeLayouts: activeLayouts) ?? typed
    }
}

private enum UnigramLexicon {
    static func load(lang: String, minLen: Int, maxLen: Int, take: Int) -> [String] {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: "\(lang)_unigrams", withExtension: "tsv", subdirectory: "LanguageModels")
        #else
        let url = Bundle.main.url(forResource: "\(lang)_unigrams", withExtension: "tsv", subdirectory: "LanguageModels")
        #endif

        guard let url else {
            // Fallback: tiny built-in list (keeps tests runnable even if resources missing).
            switch lang {
            case "ru": return Array(BuiltinLexicon.russian)
            case "he": return Array(BuiltinLexicon.hebrew)
            default: return Array(BuiltinLexicon.english)
            }
        }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return lang == "ru" ? Array(BuiltinLexicon.russian) : (lang == "he" ? Array(BuiltinLexicon.hebrew) : Array(BuiltinLexicon.english))
        }

        var out: [String] = []
        out.reserveCapacity(min(take, 200_000))

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if out.count >= take { break }
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: true)
            guard let wordRaw = parts.first, !wordRaw.isEmpty else { continue }
            let w = String(wordRaw)
            let len = w.filter { $0.isLetter }.count
            if len < minLen || len > maxLen { continue }
            out.append(w)
        }

        if out.isEmpty {
            return lang == "ru" ? Array(BuiltinLexicon.russian) : (lang == "he" ? Array(BuiltinLexicon.hebrew) : Array(BuiltinLexicon.english))
        }

        return out
    }
}

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
