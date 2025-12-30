import XCTest
@testable import OMFK

final class CommaPeriodTests: XCTestCase {
    func testKDotCommaKDot() {
        let mapper = LayoutMapper.shared
        let result = mapper.convertBest("k.,k.", from: .english, to: .russian, activeLayouts: nil)
        print("Input: k.,k.")
        print("Result: \(result ?? "nil")")
        print("Expected: люблю")
        XCTAssertEqual(result, "люблю")
    }
}
