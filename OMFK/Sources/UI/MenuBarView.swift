import SwiftUI

struct MenuBarView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var showSettings = false
    @State private var showHistory = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("O.M.F.K")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $settings.isEnabled)
                    .labelsHidden()
                    .help("Enable/disable auto-correction")
            }
            .padding()
            
            Divider()
            
            // Quick actions
            Button(action: { showSettings.toggle() }) {
                Label("Settings", systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Button(action: { showHistory.toggle() }) {
                Label("History", systemImage: "clock")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Status
            HStack {
                Circle()
                    .fill(settings.isEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(settings.isEnabled ? "Active" : "Paused")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            Button("Quit O.M.F.K") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(width: 250)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
        }
    }
}
