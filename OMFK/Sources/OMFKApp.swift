import SwiftUI
import AppKit
import os.log
import UserNotifications

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
    private var updateCheckTimer: Timer?
    
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
        
        // Setup update checking
        setupUpdateChecking()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        eventMonitor?.stop()
        updateCheckTimer?.invalidate()
    }
    
    // MARK: - Update Checking
    
    private func setupUpdateChecking() {
        // Request notification permissions
        requestNotificationPermissions()
        
        // Check for updates on launch if enabled and last check was >24h ago
        if SettingsManager.shared.checkForUpdatesAutomatically {
            let lastCheck = SettingsManager.shared.lastUpdateCheckDate ?? .distantPast
            let hoursSinceLastCheck = Date().timeIntervalSince(lastCheck) / 3600
            
            if hoursSinceLastCheck >= 24 {
                Logger.app.info("Checking for updates on launch (last check: \(hoursSinceLastCheck, privacy: .public) hours ago)")
                Task {
                    await performUpdateCheck(showNotification: true)
                }
            }
        }
        
        // Setup periodic 24-hour timer
        setupPeriodicUpdateCheck()
    }
    
    private func setupPeriodicUpdateCheck() {
        // Check every 24 hours while running
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard SettingsManager.shared.checkForUpdatesAutomatically else { return }
                Logger.app.info("Performing periodic update check")
                await self?.performUpdateCheck(showNotification: true)
            }
        }
    }
    
    private func performUpdateCheck(showNotification: Bool) async {
        let updateState = UpdateState.shared
        await updateState.checkForUpdate()
        
        // Show macOS notification if update available
        if showNotification, case .updateAvailable(let release) = updateState.lastResult {
            showUpdateNotification(version: release.version)
        }
    }
    
    /// Check if running as a proper app bundle (not via swift run)
    private var isRunningAsBundle: Bool {
        Bundle.main.bundleIdentifier != nil
    }
    
    private func requestNotificationPermissions() {
        // UNUserNotificationCenter requires a proper app bundle
        guard isRunningAsBundle else {
            Logger.app.info("Skipping notification permissions - not running as app bundle")
            return
        }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                Logger.app.error("Failed to request notification permissions: \(error.localizedDescription)")
            } else {
                Logger.app.info("Notification permissions granted: \(granted)")
            }
        }
    }
    
    private func showUpdateNotification(version: String) {
        // UNUserNotificationCenter requires a proper app bundle
        guard isRunningAsBundle else {
            Logger.app.info("Update available: v\(version) - notification skipped (not running as app bundle)")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "OMFK Update Available"
        content.body = "Version \(version) is ready to download"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "omfk.update.available",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.app.error("Failed to show update notification: \(error.localizedDescription)")
            }
        }
    }
}

