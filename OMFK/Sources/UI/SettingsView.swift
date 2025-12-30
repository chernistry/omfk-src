import SwiftUI
import AppKit

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case languages
    case hotkey
    case apps
    case learning
    case updates
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .languages: "Languages"
        case .hotkey: "Hotkey"
        case .apps: "Apps"
        case .learning: "Learning"
        case .updates: "Updates"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .languages: "globe"
        case .hotkey: "keyboard"
        case .apps: "app.badge"
        case .learning: "brain"
        case .updates: "arrow.down.circle"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var selection: SettingsPane = .general
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .navigationTitle("OMFK")
        } detail: {
            Group {
                if !searchText.isEmpty {
                    SettingsSearchResultsView(
                        query: searchText,
                        onSelectPane: { pane in
                            selection = pane
                            searchText = ""
                        }
                    )
                } else {
                    SettingsPaneView(pane: selection, settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search settings")
        .frame(minWidth: 860, minHeight: 560)
    }
}

private struct SettingsPaneView: View {
    let pane: SettingsPane
    @ObservedObject var settings: SettingsManager

    var body: some View {
        switch pane {
        case .general:
            GeneralPane(settings: settings)
        case .languages:
            LanguagesPane(settings: settings)
        case .hotkey:
            HotkeyPane(settings: settings)
        case .apps:
            AppsPane(settings: settings)
        case .learning:
            LearningPane(settings: settings)
        case .updates:
            UpdatesPane()
        case .about:
            AboutPane()
        }
    }
}

private struct GeneralPane: View {
    @ObservedObject var settings: SettingsManager
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Enable auto-correction", isOn: $settings.isEnabled)
                    .help("Automatically fix text typed in the wrong keyboard layout.")
                Toggle("Switch system layout after fix", isOn: $settings.autoSwitchLayout)
                    .help("After correcting a word, switch the active keyboard layout to match the corrected language.")
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchAtLogin = newValue
                        LaunchAtLogin.isEnabled = newValue
                    }
                ))
            } header: {
                Text("Behavior")
            }

            Section {
                Picker("Preferred language", selection: $settings.preferredLanguage) {
                    Text("English").tag(Language.english)
                    Text("Russian").tag(Language.russian)
                    Text("Hebrew").tag(Language.hebrew)
                }
                .help("When text is ambiguous, this bias helps OMFK pick the most likely intended language.")
            } header: {
                Text("Language")
            } footer: {
                Text("OMFK uses on-device language detection (n-grams + Apple recognition) and your preferences as tie-breakers.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

private struct LanguagesPane: View {
    @ObservedObject var settings: SettingsManager
    @State private var installed: [String: [InputSourceManager.InstalledLayoutVariant]] = [:]

    var body: some View {
        Form {
            Section {
                LayoutPickerRow(
                    title: "English layout",
                    selection: binding(for: "en", fallback: "us"),
                    options: installed["en"] ?? []
                )
                LayoutPickerRow(
                    title: "Russian layout",
                    selection: binding(for: "ru", fallback: "russianwin"),
                    options: installed["ru"] ?? []
                )
                LayoutPickerRow(
                    title: "Hebrew layout",
                    selection: binding(for: "he", fallback: "hebrew"),
                    options: installed["he"] ?? []
                )
            } header: {
                Text("Active Layout Variants")
            } footer: {
                Text("Pick the exact keyboard layout variants you use (e.g. Russian Phonetic, Hebrew QWERTY). This improves accuracy for layout-variant corrections.")
            }

            Section {
                Button("Auto-detect from macOS") {
                    settings.autoDetectLayouts()
                    installed = InputSourceManager.shared.installedLayoutVariantsByLanguage()
                }
            } footer: {
                Text("Auto-detect chooses the most likely installed variants and saves them as defaults.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Languages")
        .task {
            installed = InputSourceManager.shared.installedLayoutVariantsByLanguage()
        }
    }

    private func binding(for languageCode: String, fallback: String) -> Binding<String> {
        Binding(
            get: { settings.activeLayouts[languageCode] ?? fallback },
            set: { newValue in settings.activeLayouts[languageCode] = newValue }
        )
    }
}

private struct LayoutPickerRow: View {
    let title: String
    @Binding var selection: String
    let options: [InputSourceManager.InstalledLayoutVariant]

    var body: some View {
        Picker(title, selection: $selection) {
            if options.isEmpty {
                Text("No matching layouts found").tag(selection)
            } else {
                ForEach(options) { opt in
                    Text(opt.displayName).tag(opt.layoutId)
                }
            }
        }
    }
}

private struct HotkeyPane: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Form {
            Section {
                Toggle("Enable manual correction hotkey", isOn: $settings.hotkeyEnabled)
                    .help("Press the hotkey to undo or cycle between layout alternatives.")
                Picker("Hotkey", selection: $settings.hotkeyKeyCode) {
                    Text("Left Option (⌥)").tag(UInt16(58))
                    Text("Right Option (⌥)").tag(UInt16(61))
                }
                .disabled(!settings.hotkeyEnabled)
            } footer: {
                Text("Tip: You can select text and press the hotkey to cycle it between EN/RU/HE alternatives.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Hotkey")
    }
}

private struct AppsPane: View {
    @ObservedObject var settings: SettingsManager
    @State private var showingAppPicker = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable in all apps", isOn: Binding(
                    get: { settings.excludedApps.isEmpty },
                    set: { newValue in
                        if newValue {
                            settings.excludedApps.removeAll()
                        } else {
                            showingAppPicker = true
                        }
                    }
                ))
                .help("When disabled, you can exclude specific apps where you don't want auto-correction.")
            } footer: {
                Text("Excluded apps are not monitored and will never be auto-corrected.")
            }

            Section("Excluded Apps") {
                if settings.excludedApps.isEmpty {
                    EmptyStateView(title: "No excluded apps", systemImage: "checkmark.circle")
                } else {
                    List {
                        ForEach(Array(settings.excludedApps).sorted(), id: \.self) { bundleId in
                            ExcludedAppRow(bundleId: bundleId) {
                                settings.toggleApp(bundleId)
                            }
                        }
                    }
                    .frame(minHeight: 220)
                }

                Button("Add App…") { showingAppPicker = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Apps")
        .sheet(isPresented: $showingAppPicker) {
            AppPickerSheet(settings: settings, isPresented: $showingAppPicker)
        }
    }
}

private struct ExcludedAppRow: View {
    let bundleId: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            appIcon
            Text(appName)
                .lineLimit(1)
            Spacer()
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .help("Remove from excluded apps")
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "app")
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
        }
    }

    private var appName: String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleId.components(separatedBy: ".").last ?? bundleId
    }
}

private struct LearningPane: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("Learn from usage", isOn: $settings.isLearningEnabled)
                        .help("OMFK can learn from your manual undos and accepted corrections to reduce future mistakes.")
                } footer: {
                    Text("Learning never sends any personal data off-device.")
                }
            }
            .formStyle(.grouped)

            Divider()

            UserDictionaryView()
        }
        .navigationTitle("Learning")
    }
}

private struct UpdatesPane: View {
    @ObservedObject private var updateState = UpdateState.shared
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        Form {
            Section {
                UpdateCheckButton(updateState: updateState)
            }

            Section {
                Toggle("Check automatically", isOn: $settings.checkForUpdatesAutomatically)
            } footer: {
                Text("OMFK periodically checks GitHub Releases for new versions.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Updates")
    }
}

private struct AboutPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version") {
                    Text(appVersion)
                        .fontDesign(.monospaced)
                }
                Link("GitHub Repository", destination: URL(string: "https://github.com/chernistry/omfk")!)
                Link("Release Notes", destination: URL(string: "https://github.com/chernistry/omfk/releases")!)
                Link("Report a Bug", destination: URL(string: "https://github.com/chernistry/omfk/issues")!)
            }

            Section {
                Text("Oh My F***ing Keyboard automatically fixes text typed in the wrong keyboard layout (EN/RU/HE).")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
    }
}

private struct SettingsSearchResultsView: View {
    let query: String
    let onSelectPane: (SettingsPane) -> Void

    private var matches: [SettingsPane] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return SettingsPane.allCases.filter { pane in
            pane.title.lowercased().contains(q) || pane.rawValue.lowercased().contains(q)
        }
    }

    var body: some View {
        List {
            if matches.isEmpty {
                EmptyStateView(title: "No matches", systemImage: "magnifyingglass")
            } else {
                Section("Sections") {
                    ForEach(matches) { pane in
                        Button {
                            onSelectPane(pane)
                        } label: {
                            Label(pane.title, systemImage: pane.systemImage)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Search")
    }
}

private struct AppPickerSheet: View {
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
        NavigationStack {
            List {
                ForEach(runningApps, id: \.bundleIdentifier) { app in
                    Button {
                        if let bundleId = app.bundleIdentifier {
                            settings.toggleApp(bundleId)
                            isPresented = false
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                            }
                            Text(app.localizedName ?? "Unknown")
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Add Excluded App")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }
}

#Preview {
    SettingsView()
}
