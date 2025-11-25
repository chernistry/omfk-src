import XCTest
@testable import OMFK

final class LayoutMapperTests: XCTestCase {
    
    func testRussianToEnglish() {
        let result = LayoutMapper.convert("ghbdtn", from: .english, to: .russian)
        XCTAssertEqual(result, "привет")
    }
    
    func testEnglishToRussian() {
        let result = LayoutMapper.convert("привет", from: .russian, to: .english)
        XCTAssertEqual(result, "ghbdtn")
    }
    
    func testHebrewToEnglish() {
        let result = LayoutMapper.convert("שלום", from: .hebrew, to: .english)
        XCTAssertNotNil(result)
    }
    
    func testEnglishToHebrew() {
        let input = "adk"
        let result = LayoutMapper.convert(input, from: .english, to: .hebrew)
        XCTAssertNotNil(result)
    }
    
    func testSameLanguage() {
        let result = LayoutMapper.convert("hello", from: .english, to: .english)
        XCTAssertEqual(result, "hello")
    }
    
    func testMixedCase() {
        let result = LayoutMapper.convert("Ghbdtn", from: .english, to: .russian)
        XCTAssertEqual(result, "Привет")
    }
    
    func testUnsupportedConversion() {
        let result = LayoutMapper.convert("test", from: .russian, to: .hebrew)
        XCTAssertNil(result)
    }
}
