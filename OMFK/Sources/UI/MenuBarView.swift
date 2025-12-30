import SwiftUI
import AppKit

struct MenuBarView: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var history = HistoryManager.shared
    @ObservedObject private var updateState = UpdateState.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Status
        Button {
            settings.isEnabled.toggle()
        } label: {
            Label(
                settings.isEnabled ? "Enabled" : "Paused",
                systemImage: settings.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill"
            )
        }

        Divider()

        Toggle("Auto-switch layout after fix", isOn: $settings.autoSwitchLayout)
        Toggle("Manual correction hotkey", isOn: $settings.hotkeyEnabled)
        Toggle("Learning", isOn: $settings.isLearningEnabled)

        Picker("Preferred language", selection: $settings.preferredLanguage) {
            Text("English").tag(Language.english)
            Text("Russian").tag(Language.russian)
            Text("Hebrew").tag(Language.hebrew)
        }

        if updateState.isUpdateAvailable, let version = updateState.latestVersion {
            Divider()
            Button {
                updateState.openDownloadURL()
            } label: {
                Label("Update available (\(version))", systemImage: "arrow.down.circle.fill")
            }
        }

        Divider()

        Menu("Recent corrections") {
            if history.records.isEmpty {
                Text("No corrections yet")
            } else {
                ForEach(history.records.prefix(8)) { record in
                    Button {
                        Clipboard.copy(record.corrected)
                    } label: {
                        Text("\(record.original) → \(record.corrected)")
                            .lineLimit(1)
                    }
                }
            }
        }

        Divider()

        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }

        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "history")
        } label: {
            Label("History…", systemImage: "clock.arrow.circlepath")
        }

        Divider()

        Button(role: .destructive) {
            NSApp.terminate(nil)
        } label: {
            Label("Quit OMFK", systemImage: "power")
        }
    }
}

#Preview {
    MenuBarView()
        .padding()
}
