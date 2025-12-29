import XCTest
@testable import OMFK

final class CyclingTests: XCTestCase {
    var engine: CorrectionEngine!
    
    @MainActor
    override func setUp() async throws {
        let settings = SettingsManager.shared
        settings.isEnabled = true
        engine = CorrectionEngine(settings: settings)
    }
    
    @MainActor
    func testFirstRoundTwoStates() async throws {
        // "ghbdtn" (EN) -> "привет" (RU)
        // Assume active layouts include EN, RU, HE
        
        // Initial correction should return "привет" (index 1)
        // Round 1: [0]=ghbdtn, [1]=привет (hidden: [2]=hebrew_gibberish)
        
        let initial = await engine.correctLastWord("ghbdtn")
        XCTAssertEqual(initial, "привет")
        
        // First cycle: Should go back to original (index 0)
        let cycle1 = await engine.cycleCorrection()
        XCTAssertEqual(cycle1, "ghbdtn") // Undo
        
        // Second cycle: Should go to primary (index 1) - End of Round 1
        let cycle2 = await engine.cycleCorrection()
        XCTAssertEqual(cycle2, "привет")
        
        // Check if we are still in round 1 or moving to round 2 depends on logic.
        // Usually 3rd press might reveal 3rd option if logic says "after full cycle".
    }
    
    @MainActor
    func testSecondRoundThreeStates() async throws {
        // Setup: same as above
        _ = await engine.correctLastWord("ghbdtn") // -> привет
        _ = await engine.cycleCorrection() // -> ghbdtn (Undo)
        _ = await engine.cycleCorrection() // -> привет (Redo)
        
        // Now next press should reveal 3rd option if available
        // Need to ensure "ghbdtn" has a valid Hebrew mapping or some other alternative
        // "ghbdtn" in HE layout (from EN keys) is "פיונאמ" or something similar if mapped.
        // Assuming LayoutMapper produces something for EN->HE.
        
        let cycle3 = await engine.cycleCorrection()
        
        // If 3rd option exists, it should be returned. If not, it might cycle back to 0.
        // We need to verify if a 3rd option IS generated for this input.
        // "ghbdtn" map to HE: 'g'->'ע', 'h'->'י', 'b'->'נ', 'd'->'ג', 't'->'א', 'n'->'מ' -> "עינגאמ" ?
        
        // Let's assert it is NOT "ghbdtn" and NOT "привет"
        XCTAssertNotEqual(cycle3, "ghbdtn")
        XCTAssertNotEqual(cycle3, "привет")
    }
    
    @MainActor
    func testTypingResetsCyclingRound() async throws {
        _ = await engine.correctLastWord("ghbdtn")
        await engine.resetCycling()
        
        let state = await engine.hasCyclingState()
        XCTAssertFalse(state)
    }
}
