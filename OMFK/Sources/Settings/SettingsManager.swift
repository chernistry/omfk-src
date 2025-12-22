import Foundation

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "isEnabled") }
    }
    
    @Published var preferredLanguage: Language {
        didSet { UserDefaults.standard.set(preferredLanguage.rawValue, forKey: "preferredLanguage") }
    }
    
    @Published var excludedApps: Set<String> {
        didSet { UserDefaults.standard.set(Array(excludedApps), forKey: "excludedApps") }
    }
    
    @Published var autoSwitchLayout: Bool {
        didSet { UserDefaults.standard.set(autoSwitchLayout, forKey: "autoSwitchLayout") }
    }
    
    @Published var hotkeyEnabled: Bool {
        didSet { UserDefaults.standard.set(hotkeyEnabled, forKey: "hotkeyEnabled") }
    }
    
    @Published var hotkeyKeyCode: UInt16 {
        didSet { UserDefaults.standard.set(hotkeyKeyCode, forKey: "hotkeyKeyCode") }
    }
    
    @Published var activeLayouts: [String: String] {
        didSet { UserDefaults.standard.set(activeLayouts, forKey: "activeLayouts") }
    }
    
    @Published var fastPathThreshold: Double {
        didSet { UserDefaults.standard.set(fastPathThreshold, forKey: "fastPathThreshold") }
    }
    
    @Published var standardPathThreshold: Double {
        didSet { UserDefaults.standard.set(standardPathThreshold, forKey: "standardPathThreshold") }
    }
    
    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "isEnabled") as? Bool ?? true
        
        let langRaw = UserDefaults.standard.string(forKey: "preferredLanguage") ?? "en"
        self.preferredLanguage = Language(rawValue: langRaw) ?? .english
        
        let apps = UserDefaults.standard.stringArray(forKey: "excludedApps") ?? []
        self.excludedApps = Set(apps)
        
        self.autoSwitchLayout = UserDefaults.standard.object(forKey: "autoSwitchLayout") as? Bool ?? false
        self.hotkeyEnabled = UserDefaults.standard.object(forKey: "hotkeyEnabled") as? Bool ?? true
        self.hotkeyKeyCode = UInt16(UserDefaults.standard.integer(forKey: "hotkeyKeyCode") != 0 ? UserDefaults.standard.integer(forKey: "hotkeyKeyCode") : 58) // 58 = left Alt
        
        self.activeLayouts = UserDefaults.standard.object(forKey: "activeLayouts") as? [String: String] ?? [
            "en": "en_us",
            "ru": "ru_pc",
            "he": "he_standard"
        ]
        
        self.fastPathThreshold = UserDefaults.standard.object(forKey: "fastPathThreshold") as? Double ?? 0.95
        self.standardPathThreshold = UserDefaults.standard.object(forKey: "standardPathThreshold") as? Double ?? 0.70
        
        // Auto-detect installed keyboard layouts (skip in tests; allow opt-out via env var).
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
           ProcessInfo.processInfo.environment["OMFK_DISABLE_LAYOUT_AUTODETECT"] != "1" {
            detectAndUpdateLayouts()
        }
    }
    
    /// Auto-detect keyboard layout variants from macOS
    private func detectAndUpdateLayouts() {
        let detected = InputSourceManager.shared.detectInstalledLayouts()
        var updated = false
        
        for (lang, layoutID) in detected {
            if activeLayouts[lang] != layoutID {
                activeLayouts[lang] = layoutID
                updated = true
            }
        }
        
        if updated {
            // Persist the detected layouts
            UserDefaults.standard.set(activeLayouts, forKey: "activeLayouts")
        }
    }
    
    func isExcluded(bundleId: String) -> Bool {
        return excludedApps.contains(bundleId)
    }
    
    func toggleApp(_ bundleId: String) {
        if excludedApps.contains(bundleId) {
            excludedApps.remove(bundleId)
        } else {
            excludedApps.insert(bundleId)
        }
    }
}
