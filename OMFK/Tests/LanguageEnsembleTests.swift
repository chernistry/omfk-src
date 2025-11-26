import XCTest
@testable import OMFK

final class LanguageEnsembleTests: XCTestCase {
    var ensemble: LanguageEnsemble!
    
    override func setUp() {
        super.setUp()
        ensemble = LanguageEnsemble()
    }
    
    override func tearDown() {
        ensemble = nil
        super.tearDown()
    }
    
    func testBasicClassification() async {
        let context = EnsembleContext()
        
        // English
        let resEn = await ensemble.classify("hello", context: context)
        XCTAssertEqual(resEn.language, .english)
        XCTAssertEqual(resEn.layoutHypothesis, .en)
        
        // Russian
        let resRu = await ensemble.classify("привет", context: context)
        XCTAssertEqual(resRu.language, .russian)
        XCTAssertEqual(resRu.layoutHypothesis, .ru)
        
        // Hebrew
        let resHe = await ensemble.classify("שלום", context: context)
        XCTAssertEqual(resHe.language, .hebrew)
        XCTAssertEqual(resHe.layoutHypothesis, .he)
    }
    
    func testLayoutCorrectionRussian() async {
        let context = EnsembleContext()
        // "ghbdtn" is "привет" typed on English layout
        let result = await ensemble.classify("ghbdtn", context: context)
        
        XCTAssertEqual(result.language, .russian)
        XCTAssertEqual(result.layoutHypothesis, .enFromRuLayout)
        XCTAssertGreaterThan(result.confidence, 0.6)
    }
    
    func testLayoutCorrectionHebrew() async {
        let context = EnsembleContext()
        // "akuo" is "שלום" typed on English layout
        let result = await ensemble.classify("akuo", context: context)
        
        XCTAssertEqual(result.language, .hebrew)
        XCTAssertEqual(result.layoutHypothesis, .enFromHeLayout)
    }
    
    func testContextBias() async {
        // Ambiguous token "is" (could be English 'is' or part of something else)
        // Actually "is" is too short (2 chars), let's use "chat" (EN) vs "сhat" (if it were RU, but unlikely)
        // Better example: "net" (EN) vs "нет" (RU - 'ytn' on EN layout)
        
        // "ytn" -> "нет" (RU)
        // "ytn" -> "ytn" (EN - nonsense)
        
        // Without context, should prefer RU because "нет" is a valid word and "ytn" is not
        let noContext = await ensemble.classify("ytn", context: EnsembleContext())
        XCTAssertEqual(noContext.language, .russian)
        
        // With English context, might still prefer RU if the word is very strong, 
        // but let's try a case where context flips it.
        // "som" -> "som" (EN - partial) vs "ыом" (RU - nonsense)
        
        let res = await ensemble.classify("som", context: EnsembleContext(lastLanguage: .english))
        XCTAssertEqual(res.language, .english)
    }
    
    func testShortTokenFallback() async {
        let context = EnsembleContext(lastLanguage: .russian)
        // 1 char token - should fallback to context
        let result = await ensemble.classify("a", context: context)
        
        XCTAssertEqual(result.language, .russian)
        XCTAssertEqual(result.confidence, 0.5)
    }
    
    func testMixedText() async {
        // "hello мир"
        // Should detect as English or Russian depending on dominance
        // "hello" (5) + " " (1) + "мир" (3) = 9 chars. 5 Latin, 3 Cyrillic.
        // Likely English.
        
        let result = await ensemble.classify("hello мир", context: EnsembleContext())
        XCTAssertEqual(result.language, .english)
    }
}
