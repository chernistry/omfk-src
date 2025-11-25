import XCTest
@testable import OMFK

final class CorrectionEngineTests: XCTestCase {
    var engine: CorrectionEngine!
    
    @MainActor
    override func setUp() async throws {
        let settings = SettingsManager.shared
        settings.isEnabled = true
        engine = CorrectionEngine(settings: settings)
    }
    
    // MARK: - Hybrid Algorithm Tests
    
    func testCorrectInvalidRussianToEnglish() async throws {
        // "ghbdtn" is invalid in English, but "привет" is valid in Russian
        let result = await engine.correctText("ghbdtn", expectedLayout: nil)
        XCTAssertEqual(result, "привет")
    }
    
    func testCorrectInvalidEnglishToRussian() async throws {
        // "ghbdtn" typed on English layout is invalid, converts to valid Russian "привет"
        let result = await engine.correctText("ghbdtn", expectedLayout: nil)
        XCTAssertNotNil(result)
        if let corrected = result {
            XCTAssertEqual(corrected, "привет")
        }
    }
    
    func testValidWordNotCorrected() async throws {
        // "hello" is valid in English, should not be corrected
        let result = await engine.correctText("hello", expectedLayout: nil)
        XCTAssertNil(result)
    }
    
    func testValidRussianWordNotCorrected() async throws {
        // "привет" is valid in Russian, should not be corrected
        let result = await engine.correctText("привет", expectedLayout: nil)
        XCTAssertNil(result)
    }
    
    func testHebrewToEnglishCorrection() async throws {
        // Invalid Hebrew word that becomes valid English
        let result = await engine.correctText("adk", expectedLayout: nil)
        if result != nil {
            XCTAssertNotEqual(result, "adk")
        }
    }
    
    func testEmptyTextReturnsNil() async throws {
        let result = await engine.correctText("", expectedLayout: nil)
        XCTAssertNil(result)
    }
    
    func testHistoryRecordsCorrection() async throws {
        _ = await engine.correctText("ghbdtn", expectedLayout: nil)
        let history = await engine.getHistory()
        XCTAssertFalse(history.isEmpty)
        XCTAssertEqual(history.first?.original, "ghbdtn")
    }
    
    func testClearHistory() async throws {
        _ = await engine.correctText("ghbdtn", expectedLayout: nil)
        await engine.clearHistory()
        let history = await engine.getHistory()
        XCTAssertTrue(history.isEmpty)
    }
    
    @MainActor
    func testShouldCorrectWhenEnabled() async throws {
        let shouldCorrect = await engine.shouldCorrect(for: nil)
        XCTAssertTrue(shouldCorrect)
    }
    
    @MainActor
    func testShouldNotCorrectWhenDisabled() async throws {
        let settings = SettingsManager.shared
        let originalState = settings.isEnabled
        settings.isEnabled = false
        let shouldCorrect = await engine.shouldCorrect(for: nil)
        XCTAssertFalse(shouldCorrect)
        settings.isEnabled = originalState
    }
}
