import XCTest
import AppKit
import Carbon

/// E2E tests for GitHub issues using native Swift event simulation
/// These tests simulate real user typing without losing focus
final class E2EGitHubIssuesTests: XCTestCase {
    
    var testWindow: NSWindow!
    var textView: NSTextView!
    
    override func setUp() {
        super.setUp()
        
        // Create test window with text view
        testWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        let scrollView = NSScrollView(frame: testWindow.contentView!.bounds)
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        
        textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 14)
        
        scrollView.documentView = textView
        testWindow.contentView?.addSubview(scrollView)
        testWindow.makeKeyAndOrderFront(nil)
        testWindow.makeFirstResponder(textView)
    }
    
    override func tearDown() {
        testWindow?.close()
        testWindow = nil
        textView = nil
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    func typeText(_ text: String) {
        for char in text {
            textView.insertText(String(char), replacementRange: NSRange(location: textView.string.count, length: 0))
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }
    
    func typeSpace() {
        textView.insertText(" ", replacementRange: NSRange(location: textView.string.count, length: 0))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
    }
    
    func getText() -> String {
        return textView.string
    }
    
    func clearText() {
        textView.string = ""
    }
    
    // MARK: - Issue #2: Single-letter prepositions
    
    func testIssue2_PrepositionE() {
        typeText("e vtyz")
        typeSpace()
        
        let result = getText().trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(result, "у меня", "е→у preposition should convert")
    }
    
    func testIssue2_PrepositionR() {
        typeText("r cj;fktyb.")
        typeSpace()
        
        let result = getText().trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(result, "к сожалению.", "r→к preposition should convert")
    }
    
    // MARK: - Issue #3: Punctuation boundaries
    
    func testIssue3_QuestionMark() {
        typeText("ghbdtn?rfr ltkf")
        typeSpace()
        
        let result = getText().trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(result, "привет?как дела", "Question mark should trigger boundary")
    }
    
    func testIssue3_Semicolon() {
        typeText("ghbdtn; rfr ltkf")
        typeSpace()
        
        let result = getText().trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(result, "привет; как дела", "Semicolon should trigger boundary")
    }
    
    func testIssue3_Ellipsis() {
        typeText("ghbdtn...rfr ltkf")
        typeSpace()
        
        let result = getText().trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(result, "привет...как дела", "Ellipsis should trigger boundary")
    }
    
    func testIssue3_Parentheses() {
        typeText("(ghbdtn)")
        typeSpace()
        
        let result = getText().trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(result, "(привет)", "Parentheses should not block conversion")
    }
    
    func testIssue3_EmDash() {
        typeText("ghbdtn—vbh")
        typeSpace()
        
        let result = getText().trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(result, "привет—мир", "Em dash should trigger boundary")
    }
    
    // MARK: - Issue #6: Technical text protection
    
    func testIssue6_UnixPath() {
        typeText("/Users/sasha/omfk/file.swift")
        typeSpace()
        
        let result = getText().trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(result, "/Users/sasha/omfk/file.swift", "Unix path should not convert")
    }
    
    func testIssue6_Filename() {
        typeText("README.md")
        typeSpace()
        
        let result = getText().trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(result, "README.md", "Filename should not convert")
    }
    
    func testIssue6_UUID() {
        typeText("550e8400-e29b-41d4-a716-446655440000")
        typeSpace()
        
        let result = getText().trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(result, "550e8400-e29b-41d4-a716-446655440000", "UUID should not convert")
    }
    
    func testIssue6_VersionNumber() {
        typeText("v1.2.3")
        typeSpace()
        
        let result = getText().trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(result, "v1.2.3", "Version number should not convert")
    }
    
    // MARK: - Issue #7: Numbers with punctuation
    
    func testIssue7_Time() {
        typeText("15:00")
        typeSpace()
        
        let result = getText().trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(result, "15:00", "Time format should not convert")
    }
    
    func testIssue7_Date() {
        typeText("25.12.2024")
        typeSpace()
        
        let result = getText().trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(result, "25.12.2024", "Date format should not convert")
    }
    
    func testIssue7_Percentage() {
        typeText("20%")
        typeSpace()
        
        let result = getText().trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(result, "20%", "Percentage should not convert")
    }
    
    // MARK: - Issue #8: Emoji and Unicode
    
    func testIssue8_Emoji() {
        typeText("🙂 ghbdtn")
        typeSpace()
        
        let result = getText().trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(result, "🙂 привет", "Emoji should be preserved")
    }
    
    func testIssue8_Guillemets() {
        typeText("«ghbdtn»")
        typeSpace()
        
        let result = getText().trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(result, "«привет»", "Guillemets should be preserved")
    }
}
