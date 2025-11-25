import XCTest
@testable import OMFK

final class LanguageDetectorTests: XCTestCase {
    var detector: LanguageDetector!
    
    override func setUp() async throws {
        detector = LanguageDetector()
    }
    
    func testDetectRussian() async throws {
        let result = await detector.detect("привет мир")
        XCTAssertEqual(result, .russian)
    }
    
    func testDetectEnglish() async throws {
        let result = await detector.detect("hello world")
        XCTAssertEqual(result, .english)
    }
    
    func testDetectHebrew() async throws {
        let result = await detector.detect("שלום עולם")
        XCTAssertEqual(result, .hebrew)
    }
    
    func testDetectShortRussian() async throws {
        let result = await detector.detect("да")
        XCTAssertEqual(result, .russian)
    }
    
    func testDetectShortEnglish() async throws {
        let result = await detector.detect("ok")
        XCTAssertEqual(result, .english)
    }
    
    func testDetectShortHebrew() async throws {
        let result = await detector.detect("כן")
        XCTAssertEqual(result, .hebrew)
    }
    
    func testEmptyString() async throws {
        let result = await detector.detect("")
        XCTAssertNil(result)
    }
    
    // MARK: - Word Validation Tests
    
    func testValidEnglishWord() async throws {
        let isValid = await detector.isValidWord("hello", in: .english)
        XCTAssertTrue(isValid)
    }
    
    func testInvalidEnglishWord() async throws {
        let isValid = await detector.isValidWord("ghbdtn", in: .english)
        XCTAssertFalse(isValid)
    }
    
    func testValidRussianWord() async throws {
        let isValid = await detector.isValidWord("привет", in: .russian)
        XCTAssertTrue(isValid)
    }
    
    func testInvalidRussianWord() async throws {
        let isValid = await detector.isValidWord("ghbdtn", in: .russian)
        XCTAssertFalse(isValid)
    }
    
    func testValidHebrewWord() async throws {
        let isValid = await detector.isValidWord("שלום", in: .hebrew)
        XCTAssertTrue(isValid)
    }
    
    func testEmptyWordValidation() async throws {
        let isValid = await detector.isValidWord("", in: .english)
        XCTAssertFalse(isValid)
    }
}
