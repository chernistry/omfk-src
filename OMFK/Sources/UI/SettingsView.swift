import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("O.M.F.K Settings")
                .font(.title2)
                .fontWeight(.semibold)
            
            Form {
                Section("General") {
                    Toggle("Enable auto-correction", isOn: $settings.isEnabled)
                    Toggle("Auto-switch keyboard layout", isOn: $settings.autoSwitchLayout)
                    
                    Picker("Preferred language", selection: $settings.preferredLanguage) {
                        Text("English").tag(Language.english)
                        Text("Russian").tag(Language.russian)
                        Text("Hebrew").tag(Language.hebrew)
                    }
                }
                
                Section("Excluded Apps") {
                    if settings.excludedApps.isEmpty {
                        Text("No excluded apps")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(settings.excludedApps), id: \.self) { bundleId in
                            HStack {
                                Text(bundleId)
                                Spacer()
                                Button("Remove") {
                                    settings.toggleApp(bundleId)
                                }
                            }
                        }
                    }
                }
                
                Section("About") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Oh My Fucking Keyboard")
                            .font(.headline)
                        Text("Smart layout fixer for RU/EN/HE")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Version 1.0.0")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(width: 500, height: 600)
    }
}
