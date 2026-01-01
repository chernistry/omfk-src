import AppKit

@MainActor
final class TestHostAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var textView: NSTextView?
    private lazy var valueURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".omfk")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("testhost_value.txt")
    }()
    private var focusTimer: Timer?
    private var localKeyMonitor: Any?
    private var buffer = ""
    private var selectionAll = false

    private struct KeySnapshot: Sendable {
        let keyCode: Int
        let modifierFlags: NSEvent.ModifierFlags
        let characters: String?
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OMFK Test Host"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let scrollView = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView(frame: .zero)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.setAccessibilityIdentifier("omfk_test_text")
        textView.string = ""
        scrollView.documentView = textView

        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)
        window.contentView = contentView

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        self.window = window
        self.textView = textView

        buffer = ""
        selectionAll = false
        persistBuffer()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(textView)

        focusTimer?.invalidate()
        focusTimer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(enforceFocus), userInfo: nil, repeats: true)

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            let snapshot = KeySnapshot(
                keyCode: Int(event.keyCode),
                modifierFlags: event.modifierFlags,
                characters: event.characters
            )
            DispatchQueue.main.async { [weak self] in
                self?.handleKeyDown(snapshot)
            }
            return nil
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if let window, let textView {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(textView)
        }
    }

    @objc private func enforceFocus() {
        guard NSApp.isActive, let window, let textView else { return }
        if !window.isKeyWindow {
            window.makeKeyAndOrderFront(nil)
        }
        if window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }
    }

    private func handleKeyDown(_ event: KeySnapshot) {
        let isCommand = event.modifierFlags.contains(.command)
        let keyCode = event.keyCode

        // Cmd+A → select all
        if isCommand, keyCode == 0 {
            selectionAll = true
            return
        }

        // Cmd+V → paste
        if isCommand, keyCode == 9 {
            let paste = NSPasteboard.general.string(forType: .string) ?? ""
            insertText(paste)
            return
        }

        // Ignore other command shortcuts.
        if isCommand {
            return
        }

        // Delete / Backspace
        if keyCode == 51 {
            if selectionAll {
                buffer.removeAll(keepingCapacity: true)
                selectionAll = false
            } else if !buffer.isEmpty {
                buffer.removeLast()
            }
            persistBuffer()
            return
        }

        guard let chars = event.characters, !chars.isEmpty else { return }

        // Normalize CR to LF.
        let text = chars == "\r" ? "\n" : chars
        insertText(text)
    }

    private func insertText(_ text: String) {
        if selectionAll {
            buffer = text
            selectionAll = false
        } else {
            buffer.append(contentsOf: text)
        }
        persistBuffer()
    }

    private func persistBuffer() {
        let data = buffer.data(using: .utf8) ?? Data()
        try? data.write(to: valueURL, options: .atomic)
        textView?.string = buffer
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

@main
struct OMFKTestHostMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = TestHostAppDelegate()
        app.delegate = delegate
        app.run()
    }
}
