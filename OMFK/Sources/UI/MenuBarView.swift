import SwiftUI

// MARK: - Design System

enum OMFKDesign {
    static let accent = Color.accentColor
    static let success = Color.green
    static let muted = Color.secondary.opacity(0.6)
    static let spacing: CGFloat = 12
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @StateObject private var settings = SettingsManager.shared
    @Environment(\.openWindow) private var openWindow
    @State private var isHovering: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.horizontal, OMFKDesign.spacing)
            quickToggles
            Divider().padding(.horizontal, OMFKDesign.spacing)
            actions
            Divider().padding(.horizontal, OMFKDesign.spacing)
            footer
        }
        .frame(width: 280)
    }
    
    private var header: some View {
        HStack(spacing: OMFKDesign.spacing) {
            ZStack {
                Circle()
                    .fill(settings.isEnabled ? OMFKDesign.success.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 36, height: 36)
                Circle()
                    .fill(settings.isEnabled ? OMFKDesign.success : Color.gray)
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("OMFK").font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(settings.isEnabled ? "Active" : "Paused").font(.system(size: 11)).foregroundStyle(OMFKDesign.muted)
            }
            Spacer()
            Toggle("", isOn: $settings.isEnabled).toggleStyle(.switch).labelsHidden().scaleEffect(0.8)
        }
        .padding(OMFKDesign.spacing)
    }
    
    private var quickToggles: some View {
        VStack(spacing: 4) {
            QuickToggleRow(icon: "arrow.left.arrow.right", title: "Auto-switch layout", isOn: $settings.autoSwitchLayout)
            QuickToggleRow(icon: "command", title: "Hotkey enabled", isOn: $settings.hotkeyEnabled)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, OMFKDesign.spacing)
    }
    
    private var actions: some View {
        VStack(spacing: 2) {
            MenuRow(icon: "gear", title: "Settings", shortcut: "⌘,", isHovering: isHovering == "settings") {
                openWindow(id: "settings")
            }
            .onHover { isHovering = $0 ? "settings" : nil }
            
            MenuRow(icon: "clock.arrow.circlepath", title: "History", shortcut: "⌘H", isHovering: isHovering == "history") {
                openWindow(id: "history")
            }
            .onHover { isHovering = $0 ? "history" : nil }
        }
        .padding(.vertical, 4)
    }
    
    private var footer: some View {
        HStack {
            Text("v1.0").font(.system(size: 10)).foregroundStyle(OMFKDesign.muted)
            Spacer()
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("Quit").font(.system(size: 11, weight: .medium)).foregroundStyle(OMFKDesign.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(OMFKDesign.spacing)
    }
}

struct QuickToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(isOn ? OMFKDesign.accent : OMFKDesign.muted).frame(width: 20)
            Text(title).font(.system(size: 12))
            Spacer()
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().scaleEffect(0.7)
        }
        .padding(.vertical, 4)
    }
}

struct MenuRow: View {
    let icon: String
    let title: String
    var shortcut: String? = nil
    var isHovering: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(isHovering ? .primary : OMFKDesign.muted).frame(width: 20)
                Text(title).font(.system(size: 12))
                Spacer()
                if let shortcut { Text(shortcut).font(.system(size: 10, design: .rounded)).foregroundStyle(OMFKDesign.muted) }
            }
            .padding(.horizontal, OMFKDesign.spacing)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(isHovering ? Color.primary.opacity(0.1) : Color.clear))
        }
        .buttonStyle(.plain)
    }
}

#Preview { MenuBarView().frame(width: 280) }
