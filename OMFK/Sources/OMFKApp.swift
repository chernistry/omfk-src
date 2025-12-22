import SwiftUI
import AppKit
import os.log

@main
struct OMFKApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra("O.M.F.K", systemImage: "keyboard") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
        
        // Settings window (opened via WindowManager)
        Window("OMFK Settings", id: "settings") {
            SettingsView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        
        // History window
        Window("History", id: "history") {
            HistoryView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - Window Manager

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    
    func openSettings() {
        if let url = URL(string: "omfk://settings") {
            NSWorkspace.shared.open(url)
        }
        // Fallback: use Environment openWindow
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.identifier?.rawValue == "settings" {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
    
    func openHistory() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.identifier?.rawValue == "history" {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var eventMonitor: EventMonitor?
    private var correctionEngine: CorrectionEngine?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.app.info("OMFK application did finish launching")
        NSApp.setActivationPolicy(.accessory)
        
        let settings = SettingsManager.shared
        let engine = CorrectionEngine(settings: settings)
        self.correctionEngine = engine
        
        let monitor = EventMonitor(engine: engine)
        self.eventMonitor = monitor
        
        Task {
            Logger.app.info("Starting EventMonitor from AppDelegate")
            await monitor.start()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        eventMonitor?.stop()
    }
}
