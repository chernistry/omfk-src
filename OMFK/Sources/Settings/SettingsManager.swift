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
    
    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "isEnabled") as? Bool ?? true
        
        let langRaw = UserDefaults.standard.string(forKey: "preferredLanguage") ?? "en"
        self.preferredLanguage = Language(rawValue: langRaw) ?? .english
        
        let apps = UserDefaults.standard.stringArray(forKey: "excludedApps") ?? []
        self.excludedApps = Set(apps)
        
        self.autoSwitchLayout = UserDefaults.standard.object(forKey: "autoSwitchLayout") as? Bool ?? false
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
