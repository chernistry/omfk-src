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

        let en = SeedLexicon.english
        let ru = SeedLexicon.russian
        let he = SeedLexicon.hebrew

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
        let filtered = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var out: [String] = []
        out.reserveCapacity(count)

        for i in 0..<count {
            if i % 3 == 0 {
                // Phrase (2-4 words)
                let n = 2 + Int(rng.next() % 3)
                var parts: [String] = []
                parts.reserveCapacity(n)
                for _ in 0..<n {
                    parts.append(filtered[Int(rng.next() % UInt64(filtered.count))])
                }
                out.append(parts.joined(separator: " "))
            } else {
                out.append(filtered[Int(rng.next() % UInt64(filtered.count))])
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

        return LayoutMapper.shared.convert(typed, from: sourceLayout, to: decision.language, activeLayouts: activeLayouts) ?? typed
    }
}

private enum SeedLexicon {
    static let english: [String] = [
        "hi", "ok", "yes", "no", "what", "why", "hello", "thanks", "please", "sorry",
        "good", "great", "cool", "nice", "maybe", "tomorrow", "today", "work", "home",
        "friend", "where", "when", "how", "fast", "slow", "right", "left"
    ]

    static let russian: [String] = [
        "да", "нет", "что", "как", "где", "когда", "пока", "привет", "спасибо", "пожалуйста",
        "хорошо", "плохо", "дом", "работа", "сегодня", "завтра", "вчера", "друг", "люди",
        "очень", "быстро", "медленно", "право", "лево"
    ]

    static let hebrew: [String] = [
        "מה", "לא", "כן", "שלום", "טוב", "תודה", "בבקשה", "איפה", "מתי", "למה",
        "איך", "כאן", "שם", "עכשיו", "מחר", "היום", "בית", "עבודה", "חבר", "אנשים"
    ]
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

