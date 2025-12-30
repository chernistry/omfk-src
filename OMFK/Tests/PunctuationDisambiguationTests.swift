import XCTest
@testable import OMFK

final class PunctuationDisambiguationTests: XCTestCase {
    var engine: CorrectionEngine!
    var settings: SettingsManager!

    override func setUp() async throws {
        let settings = await SettingsManager.shared
        self.settings = settings
        engine = CorrectionEngine(settings: settings)

        await MainActor.run {
            settings.isEnabled = true
            // Keep thresholds permissive for deterministic unit tests.
            settings.standardPathThreshold = 0.4
        }
    }

    override func tearDown() async throws {
        engine = nil
        settings = nil
    }

    func testPunctuationAsSeparatorIsPreserved() async throws {
        let result = await engine.correctText("ghbdtn.rfr", expectedLayout: nil)
        XCTAssertEqual(result.corrected, "привет.как")
    }

    func testPunctuationAsMappedLettersIsConverted() async throws {
        let result = await engine.correctText("epyf.n", expectedLayout: nil)
        XCTAssertEqual(result.corrected, "узнают")
    }

    func testSemicolonAndDotAsMappedLettersIsConverted() async throws {
        let result = await engine.correctText("cj;fktyb.", expectedLayout: nil)
        XCTAssertEqual(result.corrected, "сожалению")
    }

    func testPhraseKSozhaleniyuCorrectsPendingPrepositionAndWord() async throws {
        await MainActor.run {
            settings.standardPathThreshold = 0.65
        }

        let first = await engine.correctText("r", expectedLayout: nil)
        XCTAssertNil(first.corrected)
        XCTAssertNil(first.pendingCorrection)

        let second = await engine.correctText("cj;fktyb.", expectedLayout: nil)
        XCTAssertEqual(second.pendingCorrection, "к")
        XCTAssertEqual(second.pendingOriginal, "r")
        XCTAssertEqual(second.corrected, "сожалению")
    }

    func testLeadingCommaCanBeMappedLetter() async throws {
        let result = await engine.correctText(",tp", expectedLayout: nil)
        XCTAssertEqual(result.corrected, "без")
    }

    func testManualSelectionUsesSmartSegmentation() async throws {
        // Hotkey correction path uses smart per-segment correction before whole-text fallbacks.
        let corrected = await engine.correctLastWord("ghbdtn.rfr ltkf")
        XCTAssertEqual(corrected, "привет.как дела")
    }

    func testVsConvertedInRussianSentenceContext() async throws {
        _ = await engine.correctText("vtyz", expectedLayout: nil) // "меня"
        _ = await engine.correctText("tcnm", expectedLayout: nil) // "есть"
        let result = await engine.correctText("vs", expectedLayout: nil) // "мы"
        XCTAssertEqual(result.corrected, "мы")
    }

    func testLtkfConvertsToDela() async throws {
        let result = await engine.correctText("ltkf", expectedLayout: nil)
        XCTAssertEqual(result.corrected, "дела")
    }

    func testRouterConfidenceForLtkfManual() async throws {
        let router = ConfidenceRouter(settings: settings)
        let ctx = DetectorContext(lastLanguage: nil)
        let manual = await router.route(token: "ltkf", context: ctx, mode: .manual)
        XCTAssertEqual(manual.layoutHypothesis, .ruFromEnLayout)
        XCTAssertGreaterThanOrEqual(manual.confidence, 0.25)
    }
}
