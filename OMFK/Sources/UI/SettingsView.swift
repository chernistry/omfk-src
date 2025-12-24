import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var selectedTab = 0
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (fixed)
            VStack(spacing: 20) {
                // App icon
                ZStack {
                    Circle()
                        .fill(.linearGradient(colors: [.blue.opacity(0.8), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 56, height: 56)
                    Image(systemName: "keyboard")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.white)
                }
                
                VStack(spacing: 4) {
                    Text("OMFK").font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("v\(appVersion)").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                
                // Segmented control
                Picker("", selection: $selectedTab) {
                    Text("General").tag(0)
                    Text("Hotkey").tag(1)
                    Text("Apps").tag(2)
                    Text("About").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)
            
            // Content (fixed height container)
            ZStack {
                switch selectedTab {
                case 0: GeneralTab(settings: settings)
                case 1: HotkeyTab(settings: settings)
                case 2: AppsTab(settings: settings)
                default: AboutTab()
                }
            }
            .frame(height: 280)
        }
        .frame(width: 380, height: 520)
        .background(.ultraThinMaterial)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @ObservedObject var settings: SettingsManager
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    
    var body: some View {
        VStack(spacing: 14) {
            GlassCard {
                SettingRow(
                    icon: "wand.and.stars",
                    iconColor: .green,
                    title: "Auto-correction",
                    subtitle: "Fix wrong layout automatically",
                    toggle: $settings.isEnabled
                )
            }
            
            GlassCard {
                SettingRow(
                    icon: "arrow.left.arrow.right",
                    iconColor: .blue,
                    title: "Auto-switch layout",
                    subtitle: "Change system layout after fix",
                    toggle: $settings.autoSwitchLayout
                )
            }
            
            GlassCard {
                SettingRow(
                    icon: "power",
                    iconColor: .purple,
                    title: "Launch at login",
                    subtitle: "Start OMFK with system",
                    toggle: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            launchAtLogin = newValue
                            LaunchAtLogin.isEnabled = newValue
                        }
                    )
                )
            }
            
            GlassCard {
                VStack(spacing: 12) {
                    Label {
                        Text("Preferred language").font(.system(size: 13, weight: .medium))
                    } icon: {
                        Image(systemName: "globe").foregroundStyle(.orange)
                    }
                    
                    HStack(spacing: 10) {
                        LangPill(lang: "EN", isSelected: settings.preferredLanguage == .english) { settings.preferredLanguage = .english }
                        LangPill(lang: "RU", isSelected: settings.preferredLanguage == .russian) { settings.preferredLanguage = .russian }
                        LangPill(lang: "HE", isSelected: settings.preferredLanguage == .hebrew) { settings.preferredLanguage = .hebrew }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Hotkey Tab

struct HotkeyTab: View {
    @ObservedObject var settings: SettingsManager
    
    var body: some View {
        VStack(spacing: 16) {
            GlassCard {
                SettingRow(
                    icon: "option",
                    iconColor: .purple,
                    title: "Manual correction",
                    subtitle: "Cycle through alternatives",
                    toggle: $settings.hotkeyEnabled
                )
            }
            
            GlassCard {
                HStack {
                    Label {
                        Text("Hotkey").font(.system(size: 13, weight: .medium))
                    } icon: {
                        Image(systemName: "command").foregroundStyle(.indigo)
                    }
                    
                    Spacer()
                    
                    Text(keyName(settings.hotkeyKeyCode))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .opacity(settings.hotkeyEnabled ? 1 : 0.5)
            
            // Tip
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text("Press hotkey to undo or cycle corrections")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
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
    @State private var showingAppPicker = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Tip
            HStack(spacing: 10) {
                Image(systemName: "app.badge.checkmark")
                    .foregroundStyle(.blue)
                Text("Exclude apps from auto-correction")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            
            GlassCard {
                VStack(spacing: 12) {
                    HStack {
                        Text("Excluded").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button(action: { showingAppPicker = true }) {
                            Label("Add app", systemImage: "plus")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                    
                    if settings.excludedApps.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(.tertiary)
                            Text("No excluded apps")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(Array(settings.excludedApps), id: \.self) { bundleId in
                                    AppRow(bundleId: bundleId) { settings.toggleApp(bundleId) }
                                }
                            }
                        }
                        .frame(maxHeight: 120)
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showingAppPicker) {
            AppPickerSheet(settings: settings, isPresented: $showingAppPicker)
        }
    }
}

struct AppPickerSheet: View {
    @ObservedObject var settings: SettingsManager
    @Binding var isPresented: Bool
    
    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .filter { !settings.excludedApps.contains($0.bundleIdentifier ?? "") }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Select App to Exclude")
                .font(.headline)
            
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(action: {
                            if let bundleId = app.bundleIdentifier {
                                settings.toggleApp(bundleId)
                                isPresented = false
                            }
                        }) {
                            HStack(spacing: 12) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                }
                                Text(app.localizedName ?? "Unknown")
                                    .font(.system(size: 13))
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 300)
            
            Button("Cancel") { isPresented = false }
                .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(width: 300)
    }
}

// MARK: - About Tab

struct AboutTab: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 20)
            
            VStack(spacing: 6) {
                Text("Oh My F***ing Keyboard")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            
            Text("Version \(appVersion) (\(buildNumber))")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
            
            Spacer(minLength: 20)
            
            VStack(spacing: 4) {
                Text("Created by Alex Chernysh")
                    .font(.system(size: 12, weight: .medium))
                Text("© 2025")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            
            Spacer(minLength: 20)
        }
        .padding(20)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Components

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass()
    }
}

struct SettingRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var toggle: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $toggle)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

struct LangPill: View {
    let lang: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(lang)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? .blue : .clear, in: Capsule())
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct AppRow: View {
    let bundleId: String
    let onRemove: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app").frame(width: 24, height: 24).foregroundStyle(.secondary)
            }
            
            Text(appName).font(.system(size: 12)).lineLimit(1)
            Spacer()
            
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(isHovered ? .white.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .onHover { isHovered = $0 }
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
    func liquidGlass(in shape: some Shape = RoundedRectangle(cornerRadius: 14)) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

#Preview { SettingsView() }
