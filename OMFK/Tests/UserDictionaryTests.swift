import XCTest
@testable import OMFK

final class UserDictionaryTests: XCTestCase {
    var dictionary: UserDictionary!
    var tempURL: URL!
    
    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        tempURL = tempDir.appendingPathComponent(UUID().uuidString + ".json")
        dictionary = UserDictionary(storageURL: tempURL)
    }
    
    override func tearDown() async throws {
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    func testAddAndLookup() async {
        let id = UUID()
        let rule = UserDictionaryRule(
            id: id,
            token: "TestToken",
            matchMode: .exact,
            scope: .global,
            action: .keepAsIs,
            source: .manual,
            evidence: RuleEvidence(),
            createdAt: Date(),
            updatedAt: Date()
        )
        
        await dictionary.addRule(rule)
        
        // Exact case match
        var found = await dictionary.lookup("TestToken")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.token, "TestToken")
        
        // Case insensitive lookup should also work due to normalization in lookup
        found = await dictionary.lookup("testtoken")
        XCTAssertNotNil(found)
    }
    
    func testLearningUndoFlow() async {
        let token = "UndoMe"
        
        // 1. Initial State: No rule
        var rule = await dictionary.lookup(token)
        XCTAssertNil(rule)
        
        // 2. First Undo (AutoReject) -> Creates pending rule (action: .none)
        await dictionary.recordAutoReject(token: token)
        rule = await dictionary.lookup(token)
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.action, RuleAction.none)
        XCTAssertEqual(rule?.evidence.autoRejectCount, 1)
        
        // 3. Second Undo -> Threshold reached -> action: .keepAsIs
        await dictionary.recordAutoReject(token: token)
        rule = await dictionary.lookup(token)
        XCTAssertEqual(rule?.action, .keepAsIs)
        XCTAssertEqual(rule?.evidence.autoRejectCount, 2)
    }
    
    func testLearningManualApplyFlow() async {
        let token = "ApplyMe"
        let hyp = "enFromRuLayout"
        
        // 1. Learn directly from manual apply
        await dictionary.recordManualApply(token: token, hypothesis: hyp)
        
        var rule = await dictionary.lookup(token)
        XCTAssertNotNil(rule)
        
        if case .preferHypothesis(let h) = rule?.action {
            XCTAssertEqual(h, hyp)
        } else {
            XCTFail("Action should be preferHypothesis")
        }
        XCTAssertEqual(rule?.evidence.manualApplyCount, 1)
        
        // 2. Further applies just increment count
        await dictionary.recordManualApply(token: token, hypothesis: hyp)
        rule = await dictionary.lookup(token)
        XCTAssertEqual(rule?.evidence.manualApplyCount, 2)
    }
    
    func testValidation() async {
        // Test manual apply overrides pending state
        let token = "MixedState"
        
        // Pending state
        await dictionary.recordAutoReject(token: token)
        var rule = await dictionary.lookup(token)
        XCTAssertEqual(rule?.action, RuleAction.none)
        
        // Now manual apply -> Should switch to preferHypothesis
        await dictionary.recordManualApply(token: token, hypothesis: "ru") // e.g. .ru hypothesis
        rule = await dictionary.lookup(token)
        
        if case .preferHypothesis(let h) = rule?.action {
            XCTAssertEqual(h, "ru")
        } else {
            XCTFail("Should switch to preferHypothesis from none")
        }
    }
    
    func testUnlearning() async {
        let token = "KeepMe"
        
        // Setup learned rule
        await dictionary.recordAutoReject(token: token)
        await dictionary.recordAutoReject(token: token)
        var rule = await dictionary.lookup(token)
        XCTAssertEqual(rule?.action, .keepAsIs)
        
        // 1. Override -> Still there
        await dictionary.recordOverride(token: token)
        rule = await dictionary.lookup(token)
        XCTAssertEqual(rule?.evidence.overrideCount, 1)
        XCTAssertNotNil(rule)
        
        // 2. Override -> Removed
        await dictionary.recordOverride(token: token)
        rule = await dictionary.lookup(token)
        XCTAssertNil(rule)
    }
    
    func testPersistence() async {
        let token = "Persist"
        await dictionary.recordAutoReject(token: token)
        
        // Re-init with same URL
        let newDict = UserDictionary(storageURL: tempURL)
        let rule = await newDict.lookup(token)
        
        XCTAssertNotNil(rule)
        // recordAutoReject normalizes (lowercases) the token when creating rule
        XCTAssertEqual(rule?.token, "persist")
    }
}
