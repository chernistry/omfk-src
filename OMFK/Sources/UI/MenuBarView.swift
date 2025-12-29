import SwiftUI

struct MenuBarView: View {
    @StateObject private var settings = SettingsManager.shared
    @ObservedObject private var updateState = UpdateState.shared
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(spacing: 16) {
            // Update available indicator
            if updateState.isUpdateAvailable, let version = updateState.latestVersion {
                UpdateAvailableButton(version: version) {
                    updateState.openDownloadURL()
                }
                .padding(.bottom, -8)
            }
            
            // Status pill
            statusPill
            
            // Quick controls
            VStack(spacing: 12) {
                ControlRow(icon: "arrow.left.arrow.right", title: "Auto-switch", isOn: $settings.autoSwitchLayout)
                ControlRow(icon: "option", title: "Hotkey", isOn: $settings.hotkeyEnabled)
            }
            .padding(.horizontal, 4)
            
            // Actions
            HStack(spacing: 12) {
                ActionButton(icon: "gear", title: "Settings") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                }
                ActionButton(icon: "clock", title: "History") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "history")
                }
            }
            
            // Quit
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("Quit OMFK")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(width: 280)
    }
    
    private var statusPill: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(settings.isEnabled ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
                .shadow(color: settings.isEnabled ? .green.opacity(0.5) : .clear, radius: 4)
            
            Text(settings.isEnabled ? "Active" : "Paused")
                .font(.system(size: 13, weight: .medium))
            
            Spacer()
            
            Toggle("", isOn: $settings.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.75)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .liquidGlass()
    }
}

struct ControlRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn ? .blue : .secondary)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 13))
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.75)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .light))
                Text(title)
                    .font(.system(size: 11))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.1))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

#Preview { MenuBarView() }
