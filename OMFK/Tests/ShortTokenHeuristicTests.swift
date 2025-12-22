import XCTest
@testable import OMFK

final class ShortTokenHeuristicTests: XCTestCase {
    func testEnsemblePrefersHebrewFromEnglishForMH() async throws {
        let validator = MockWordValidator(validWords: [
            .english: ["hi", "ok", "yes"],
            .russian: ["да", "нет"],
            .hebrew: ["מה", "לא", "כן"]
        ])

        let ensemble = LanguageEnsemble(wordValidator: validator)
        let context = EnsembleContext(
            lastLanguage: nil,
            activeLayouts: ["en": "us", "ru": "russianwin", "he": "hebrew_qwerty"]
        )

        let decision = await ensemble.classify("mh", context: context)
        XCTAssertEqual(decision.layoutHypothesis, .heFromEnLayout)
        XCTAssertGreaterThan(decision.confidence, 0.7)
    }
}

