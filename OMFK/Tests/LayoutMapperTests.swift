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
    
    func testRussianToHebrew() {
        // RU→HE via composition (RU→EN→HE)
        let result = LayoutMapper.convert("ghbdtn", from: .russian, to: .hebrew)
        XCTAssertNotNil(result)
        // Verify it's different from original
        XCTAssertNotEqual(result, "ghbdtn")
    }
    
    func testHebrewToRussian() {
        // HE→RU via composition (HE→EN→RU)
        let result = LayoutMapper.convert("שלום", from: .hebrew, to: .russian)
        XCTAssertNotNil(result)
        // Verify it's different from original
        XCTAssertNotEqual(result, "שלום")
    }
    
    func testRussianHebrewRoundTrip() {
        // Test reversibility: RU→HE→RU should preserve structure
        let original = "привет"
        guard let toHebrew = LayoutMapper.convert(original, from: .russian, to: .hebrew),
              let backToRussian = LayoutMapper.convert(toHebrew, from: .hebrew, to: .russian) else {
            XCTFail("Conversion failed")
            return
        }
        XCTAssertEqual(backToRussian, original)
    }
    
    func testHebrewRussianRoundTrip() {
        // Test reversibility: HE→RU→HE should preserve structure
        let original = "שלום"
        guard let toRussian = LayoutMapper.convert(original, from: .hebrew, to: .russian),
              let backToHebrew = LayoutMapper.convert(toRussian, from: .russian, to: .hebrew) else {
            XCTFail("Conversion failed")
            return
        }
        XCTAssertEqual(backToHebrew, original)
    }
    
    func testAllLanguagePairs() {
        // Verify all 6 conversion pairs work
        let testText = "test"
        
        // RU↔EN (direct)
        XCTAssertNotNil(LayoutMapper.convert(testText, from: .russian, to: .english))
        XCTAssertNotNil(LayoutMapper.convert(testText, from: .english, to: .russian))
        
        // HE↔EN (direct)
        XCTAssertNotNil(LayoutMapper.convert(testText, from: .hebrew, to: .english))
        XCTAssertNotNil(LayoutMapper.convert(testText, from: .english, to: .hebrew))
        
        // RU↔HE (composition)
        XCTAssertNotNil(LayoutMapper.convert(testText, from: .russian, to: .hebrew))
        XCTAssertNotNil(LayoutMapper.convert(testText, from: .hebrew, to: .russian))
    }
}
