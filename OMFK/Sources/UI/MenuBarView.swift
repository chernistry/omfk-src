import SwiftUI

struct MenuBarView: View {
    @StateObject private var settings = SettingsManager.shared
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header with Liquid Glass
            statusHeader
            
            Divider()
            
            // Quick toggles
            VStack(spacing: 2) {
                MenuToggleRow(
                    title: "Auto-switch layout",
                    isOn: $settings.autoSwitchLayout
                )
                MenuToggleRow(
                    title: "Hotkey enabled",
                    isOn: $settings.hotkeyEnabled
                )
            }
            .padding(.vertical, 6)
            
            Divider()
            
            // Actions
            VStack(spacing: 2) {
                MenuActionRow(title: "Settings...", shortcut: "⌘,") {
                    openWindow(id: "settings")
                }
                MenuActionRow(title: "History") {
                    openWindow(id: "history")
                }
            }
            .padding(.vertical, 6)
            
            Divider()
            
            // Quit
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("Quit OMFK")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
        }
        .frame(width: 240)
    }
    
    private var statusHeader: some View {
        HStack(spacing: 10) {
            // Status indicator with glass effect on macOS 26
            statusIndicator
            
            Text(settings.isEnabled ? "Active" : "Paused")
                .font(.headline)
            
            Spacer()
            
            Toggle("", isOn: $settings.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
    
    @ViewBuilder
    private var statusIndicator: some View {
        if #available(macOS 26.0, *) {
            Circle()
                .fill(settings.isEnabled ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 10, height: 10)
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            Circle()
                .fill(settings.isEnabled ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
        }
    }
}

struct MenuToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    @State private var isHovered = false
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(hoverBackground)
        .cornerRadius(4)
        .padding(.horizontal, 6)
        .onHover { isHovered = $0 }
    }
    
    @ViewBuilder
    private var hoverBackground: some View {
        if isHovered {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 4))
            } else {
                Color.accentColor.opacity(0.1)
            }
        } else {
            Color.clear
        }
    }
}

struct MenuActionRow: View {
    let title: String
    var shortcut: String? = nil
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(hoverBackground)
            .cornerRadius(4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
    
    @ViewBuilder
    private var hoverBackground: some View {
        if isHovered {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 4))
            } else {
                Color.accentColor.opacity(0.1)
            }
        } else {
            Color.clear
        }
    }
}

#Preview { MenuBarView() }
