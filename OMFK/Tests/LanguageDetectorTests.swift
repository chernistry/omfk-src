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
}
