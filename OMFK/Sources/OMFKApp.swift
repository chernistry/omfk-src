import SwiftUI
import AppKit

@main
struct OMFKApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra("O.M.F.K", systemImage: "keyboard") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var eventMonitor: EventMonitor?
    private var correctionEngine: CorrectionEngine?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        let settings = SettingsManager.shared
        let engine = CorrectionEngine(settings: settings)
        self.correctionEngine = engine
        
        let monitor = EventMonitor(engine: engine)
        self.eventMonitor = monitor
        
        Task {
            await monitor.start()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        eventMonitor?.stop()
    }
}
