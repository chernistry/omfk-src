import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            
            // Content based on selected tab
            Group {
                switch selectedTab {
                case 0: GeneralTab(settings: settings)
                case 1: HotkeyTab(settings: settings)
                case 2: AppsTab(settings: settings)
                default: GeneralTab(settings: settings)
                }
            }
        }
        .frame(width: 420, height: 480)
        .background(.ultraThinMaterial)
    }
    
    private var header: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 48, height: 48)
                    Image(systemName: "keyboard")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("OMFK").font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("Oh My Fucking Keyboard").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            Picker("", selection: $selectedTab) {
                Text("General").tag(0)
                Text("Hotkey").tag(1)
                Text("Apps").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            
            Text("Version 1.0.0").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(20)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @ObservedObject var settings: SettingsManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Auto-correction").font(.system(size: 13, weight: .medium))
                            Text("Automatically fix wrong keyboard layout").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.isEnabled).toggleStyle(.switch).labelsHidden()
                    }
                }
                
                SettingsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Auto-switch layout").font(.system(size: 13, weight: .medium))
                            Text("Switch system layout after correction").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.autoSwitchLayout).toggleStyle(.switch).labelsHidden()
                    }
                }
                
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Preferred language").font(.system(size: 13, weight: .medium))
                        HStack(spacing: 8) {
                            LanguageButton(label: "EN", isSelected: settings.preferredLanguage == .english) { settings.preferredLanguage = .english }
                            LanguageButton(label: "RU", isSelected: settings.preferredLanguage == .russian) { settings.preferredLanguage = .russian }
                            LanguageButton(label: "HE", isSelected: settings.preferredLanguage == .hebrew) { settings.preferredLanguage = .hebrew }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Hotkey Tab

struct HotkeyTab: View {
    @ObservedObject var settings: SettingsManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Manual correction").font(.system(size: 13, weight: .medium))
                            Text("Press hotkey to cycle through corrections").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.hotkeyEnabled).toggleStyle(.switch).labelsHidden()
                    }
                }
                
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Current hotkey").font(.system(size: 13, weight: .medium))
                        HStack {
                            HotkeyDisplay(keyCode: settings.hotkeyKeyCode)
                            Spacer()
                            Text("Default: Left ⌥").font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
                    }
                }
                .opacity(settings.hotkeyEnabled ? 1 : 0.5)
                
                InfoCard(icon: "lightbulb", text: "Press the hotkey to undo auto-correction or manually convert selected text")
            }
            .padding(20)
        }
    }
}

// MARK: - Apps Tab

struct AppsTab: View {
    @ObservedObject var settings: SettingsManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                InfoCard(icon: "app.badge.checkmark", text: "Exclude apps where you don't want auto-correction")
                
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Excluded apps").font(.system(size: 13, weight: .medium))
                            Spacer()
                            Button(action: addCurrentApp) {
                                Label("Add current", systemImage: "plus.circle").font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }
                        
                        if settings.excludedApps.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle").font(.system(size: 24)).foregroundStyle(.tertiary)
                                    Text("No excluded apps").font(.system(size: 12)).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 20)
                                Spacer()
                            }
                        } else {
                            VStack(spacing: 8) {
                                ForEach(Array(settings.excludedApps), id: \.self) { bundleId in
                                    ExcludedAppRow(bundleId: bundleId) { settings.toggleApp(bundleId) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
    
    private func addCurrentApp() {
        if let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           bundleId != Bundle.main.bundleIdentifier {
            settings.toggleApp(bundleId)
        }
    }
}

// MARK: - Components

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(.background).shadow(color: .black.opacity(0.05), radius: 2, y: 1))
    }
}

struct InfoCard: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.blue)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.blue.opacity(0.1)))
    }
}

struct LanguageButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .frame(width: 48, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor : Color.primary.opacity(0.05)))
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct HotkeyDisplay: View {
    let keyCode: UInt16
    var body: some View {
        Text(keySymbol)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.1)))
    }
    private var keySymbol: String {
        switch keyCode {
        case 58: return "⌥ Left Option"
        case 61: return "⌥ Right Option"
        case 59: return "⌃ Left Control"
        case 62: return "⌃ Right Control"
        default: return "Key \(keyCode)"
        }
    }
}

struct ExcludedAppRow: View {
    let bundleId: String
    let onRemove: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 10) {
            appIcon
            Text(appName).font(.system(size: 12)).lineLimit(1)
            Spacer()
            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(isHovering ? Color.primary.opacity(0.05) : Color.clear))
        .onHover { isHovering = $0 }
    }
    
    @ViewBuilder
    private var appIcon: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: "app").font(.system(size: 16)).frame(width: 24, height: 24).foregroundStyle(.secondary)
        }
    }
    
    private var appName: String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleId.components(separatedBy: ".").last ?? bundleId
    }
}

#Preview { SettingsView() }
