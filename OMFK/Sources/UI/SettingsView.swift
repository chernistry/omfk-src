import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(0)
            
            HotkeyTab(settings: settings)
                .tabItem { Label("Hotkey", systemImage: "command") }
                .tag(1)
            
            AppsTab(settings: settings)
                .tabItem { Label("Apps", systemImage: "app.badge") }
                .tag(2)
        }
        .frame(width: 420, height: 320)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @ObservedObject var settings: SettingsManager
    
    var body: some View {
        Form {
            Section {
                Toggle("Auto-correction", isOn: $settings.isEnabled)
                Toggle("Auto-switch layout", isOn: $settings.autoSwitchLayout)
            } header: {
                Text("Behavior")
            }
            
            Section {
                Picker("Preferred language", selection: $settings.preferredLanguage) {
                    Text("🇺🇸 English").tag(Language.english)
                    Text("🇷🇺 Russian").tag(Language.russian)
                    Text("🇮🇱 Hebrew").tag(Language.hebrew)
                }
            } header: {
                Text("Language")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

// MARK: - Hotkey Tab

struct HotkeyTab: View {
    @ObservedObject var settings: SettingsManager
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable hotkey", isOn: $settings.hotkeyEnabled)
                
                if settings.hotkeyEnabled {
                    LabeledContent("Key") {
                        Text(keyName(settings.hotkeyKeyCode))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Manual Correction")
            }
            
            Section {
                Text("Press the hotkey to cycle through layout alternatives for selected text or last typed word.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("How it works")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
    
    private func keyName(_ code: UInt16) -> String {
        switch code {
        case 58: return "⌥ Left Option"
        case 61: return "⌥ Right Option"
        default: return "Key \(code)"
        }
    }
}

// MARK: - Apps Tab

struct AppsTab: View {
    @ObservedObject var settings: SettingsManager
    
    var body: some View {
        Form {
            Section {
                if settings.excludedApps.isEmpty {
                    ContentUnavailableView {
                        Label("No Excluded Apps", systemImage: "checkmark.circle")
                    } description: {
                        Text("All apps will use auto-correction")
                    }
                } else {
                    ForEach(Array(settings.excludedApps), id: \.self) { bundleId in
                        AppRow(bundleId: bundleId) {
                            settings.toggleApp(bundleId)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Excluded Apps")
                    Spacer()
                    Button("Add Current App") {
                        addCurrentApp()
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    private func addCurrentApp() {
        if let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           bundleId != Bundle.main.bundleIdentifier {
            settings.toggleApp(bundleId)
        }
    }
}

// MARK: - Components

struct AppRow: View {
    let bundleId: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app")
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
            }
            
            Text(appName)
                .lineLimit(1)
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var appName: String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleId.components(separatedBy: ".").last ?? bundleId
    }
}

// MARK: - Liquid Glass Modifier (macOS 26+)

extension View {
    /// Apply Liquid Glass effect on macOS 26+, fallback to ultraThinMaterial on older versions
    @ViewBuilder
    func liquidGlass(in shape: some Shape = RoundedRectangle(cornerRadius: 12)) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
    
    /// Apply interactive Liquid Glass effect on macOS 26+
    @ViewBuilder
    func liquidGlassInteractive(in shape: some Shape = RoundedRectangle(cornerRadius: 12)) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

#Preview { SettingsView() }
